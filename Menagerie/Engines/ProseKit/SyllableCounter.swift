import Foundation

/// Estimates how many syllables English words have, from their spelling.
///
/// English spelling hides its syllables, so the counter starts from the
/// classic heuristic, one syllable per group of adjacent vowels, and then
/// corrects the ways that goes wrong most often:
///
/// * a silent final *e* ("make"), kept after a consonant and *l* or *r*
///   ("table", "acre");
/// * the endings *-es* and *-ed*, silent except after sibilants ("boxes") and
///   after *t* or *d* ("wanted");
/// * *y*, a consonant in "yes" and "player" but a vowel in "gym" and "flyer";
/// * vowel pairs that straddle two syllables ("li-on", "cre-ate", "be-ing",
///   "vid-e-o", "ac-tu-al");
/// * suffixes and compounds that hide a silent *e* ("hope-less",
///   "some-thing", "home-work");
/// * endings where a consonant carries the syllable ("pris-m", "rhy-thm").
///
/// A lexicon of exceptions covers words that no rule gets right, such as
/// "business" and "recipe". Numbers are read aloud ("1984" is "nineteen
/// eighty-four", five syllables), short acronyms and acronyms without vowels
/// are spelled out ("BBC" has three), and dotted abbreviations are read
/// letter by letter. Words in other scripts count as one syllable.
///
/// Checked against the CMU Pronouncing Dictionary, the counter agrees on
/// 98.7% of the 10,000 most frequent English words that aren't acronyms, and
/// on 99.5% of the 3,000 most frequent. Most disagreements are names and
/// words that dictionaries themselves split differently ("fire" has one
/// syllable here and two in CMU).
public struct SyllableCounter: Sendable {
    /// A counter with the built-in English lexicon.
    public static let english = SyllableCounter()

    /// Syllable counts for words the rules get wrong, keyed by the lowercase
    /// word.
    public let exceptions: [String: Int]

    /// Creates a counter whose lexicon adds `additionalExceptions` to (or
    /// overrides) the built-in one.
    public init(additionalExceptions: [String: Int] = [:]) {
        var lexicon = SyllableLexicon.exceptions
        for (word, count) in additionalExceptions {
            lexicon[ProseTokenizer.normalize(word)] = count
        }
        exceptions = lexicon
    }

    /// The number of syllables in `word`. Hyphenated compounds are the sum of
    /// their parts. Returns 0 only when `word` has no letters or digits.
    public func syllables(in word: String) -> Int {
        var total = 0
        var piece = ""
        for character in word {
            if character.isLetter || character.isNumber || character == "." || character == ","
                || ProseTokenizer.apostrophes.contains(character) {
                piece.append(character)
            } else if !piece.isEmpty {
                total += syllables(inPiece: piece)
                piece = ""
            }
        }
        if !piece.isEmpty {
            total += syllables(inPiece: piece)
        }
        return total
    }

    // MARK: - Pieces

    private static let edgePunctuation = CharacterSet(charactersIn: ".,'\u{2019}\u{02BC}")

    /// A piece is a run of letters, digits, periods, commas and apostrophes.
    private func syllables(inPiece raw: String) -> Int {
        let piece = raw.trimmingCharacters(in: Self.edgePunctuation)
        guard !piece.isEmpty else { return 0 }
        let hasLetters = piece.contains(where: \.isLetter)
        let hasDigits = piece.contains(where: SpokenNumber.isDigit)

        if !hasLetters {
            return hasDigits ? SpokenNumber.syllables(in: piece) : 0
        }
        if hasDigits {
            return mixedSyllables(piece)
        }
        if piece.contains(".") {
            let parts = piece.split(separator: ".")
            // "U.S." and "e.g." are read letter by letter.
            if parts.allSatisfy({ $0.count == 1 }) {
                return Self.spelledOut(parts.compactMap(\.first))
            }
            return parts.reduce(0) { $0 + syllables(inPiece: String($1)) }
        }
        if piece.contains(",") {
            return piece.split(separator: ",").reduce(0) { $0 + syllables(inPiece: String($1)) }
        }
        return wordSyllables(piece)
    }

    /// Letters and digits together, as in "MP3", "4K" or "1990s".
    private func mixedSyllables(_ piece: String) -> Int {
        var total = 0
        var run = ""
        var runIsNumber = false
        var previousRunWasNumber = false

        func flush() {
            guard !run.isEmpty else { return }
            if runIsNumber {
                total += SpokenNumber.syllables(in: run)
            } else if previousRunWasNumber, Self.numberSuffixes.contains(run.lowercased()) {
                // "1990s" and "21st" are read as their number.
            } else {
                total += wordSyllables(run)
            }
            previousRunWasNumber = runIsNumber
            run = ""
        }

        for character in piece {
            let isNumberPart = SpokenNumber.isDigit(character) || (runIsNumber && (character == "." || character == ","))
            if !run.isEmpty, isNumberPart != runIsNumber {
                flush()
            }
            runIsNumber = isNumberPart
            run.append(character)
        }
        flush()
        return total
    }

    private static let numberSuffixes: Set<String> = ["s", "st", "nd", "rd", "th"]

    /// One word made of letters, possibly with apostrophes.
    private func wordSyllables(_ word: String) -> Int {
        let letters = word.filter(\.isLetter)
        let isShouted = letters.count >= 3 && ProseStopwords.english.contains(letters.lowercased())
        if letters.count >= 2, letters.allSatisfy(\.isUppercase), !isShouted {
            // Short acronyms and those without vowels are spelled out: "US",
            // "FBI", "HTML". Longer ones with vowels are said as words: "NASA".
            // Capitalized function words ("THE") are just shouted.
            let hasVowel = letters.contains { "AEIOUY".contains($0) }
            if letters.count <= 3 || !hasVowel {
                return Self.spelledOut(letters)
            }
        }

        let normalized = ProseTokenizer.normalize(word)
        if let known = exceptions[normalized] {
            return known
        }
        if let apostrophe = normalized.lastIndex(of: "'") {
            let stem = String(normalized[..<apostrophe])
            let clitic = String(normalized[normalized.index(after: apostrophe)...])
            return contractionSyllables(stem: stem, clitic: clitic)
        }
        return spellingSyllables(normalized)
    }

    /// "didn't", "should've", "it'll", "James's": the clitic adds a syllable
    /// only when the stem ends in a consonant that can't absorb it.
    private func contractionSyllables(stem: String, clitic: String) -> Int {
        guard !stem.isEmpty else { return spellingSyllables(clitic) }
        let last = stem.last ?? "a"
        let endsInVowel = "aeiouy".contains(last)
        switch clitic {
        case "t" where stem.hasSuffix("n"):
            let base = String(stem.dropLast())
            if let before = base.last, !"aeiouy".contains(before) {
                return spellingSyllables(base) + 1                // "did-n't", "could-n't"
            }
            return spellingSyllables(stem + clitic)               // "don't", "can't"
        case "ve", "ll", "d", "re":
            return spellingSyllables(stem) + (endsInVowel ? 0 : 1)  // "should-'ve", "it-'ll"
        case "s":
            let sibilant = ["s", "x", "z", "ch", "sh", "ce", "ge", "se"].contains { stem.hasSuffix($0) }
            return spellingSyllables(stem) + (sibilant ? 1 : 0)   // "James-'s"
        case "m", "":
            return spellingSyllables(stem)
        default:
            return spellingSyllables(stem + clitic)               // "O'Brien"
        }
    }

    /// Syllables in a lowercase word, spelled in any Latin alphabet.
    private func spellingSyllables(_ word: String) -> Int {
        guard let spelling = LatinSpelling(word) else { return 1 }
        return count(
            spelling.letters,
            stressedFinalE: spelling.stressedFinalE,
            forcedSplits: spelling.forcedSplits
        )
    }

    /// Applies the lexicon, then affixes, then the spelling rules.
    private func count(
        _ letters: [UInt8],
        stressedFinalE: Bool = false,
        forcedSplits: Set<Int> = [],
        pronouncedEd: Bool = false
    ) -> Int {
        guard !letters.isEmpty else { return 0 }
        if let known = exceptions[String(decoding: letters, as: UTF8.self)] {
            return known
        }
        // "Mc" is a syllable of its own: "Mc-Don-ald".
        if letters.count > 3, letters[0] == UInt8(ascii: "m"), letters[1] == UInt8(ascii: "c"),
           !EnglishSpelling.isVowelLetter(letters[2]) {
            return 1 + count(Array(letters.dropFirst(2)))
        }
        if forcedSplits.isEmpty, !stressedFinalE {
            if let split = SyllableLexicon.suffixSplit(letters) {
                return count(split.root, pronouncedEd: split.keepsEd) + split.syllables
            }
            if let rest = SyllableLexicon.compoundRemainder(letters) {
                return 1 + count(rest)
            }
        }
        return EnglishSpelling.syllables(
            in: letters,
            stressedFinalE: stressedFinalE,
            forcedSplits: forcedSplits,
            pronouncedEd: pronouncedEd
        )
    }

    /// Letters read one by one. Every letter name is one syllable except W.
    private static func spelledOut<Letters: Collection>(_ letters: Letters) -> Int where Letters.Element == Character {
        letters.reduce(0) { $0 + ($1 == "W" || $1 == "w" ? 3 : 1) }
    }
}

/// A word reduced to the letters a–z, remembering the accents that change
/// how it is said.
struct LatinSpelling {
    private(set) var letters: [UInt8] = []
    /// "café", "cafés", "Brontë": the accent says the last e is sounded.
    private(set) var stressedFinalE = false
    /// Vowels with a diaeresis start a new syllable: "na-ïve", "Zo-ë".
    private(set) var forcedSplits: Set<Int> = []

    private static let replacements: [Character: String] = [
        "æ": "ae", "œ": "oe", "ø": "o", "ß": "ss", "ł": "l", "đ": "d", "ð": "d", "þ": "th", "ı": "i",
    ]

    /// Returns nil when the word has no Latin letters at all.
    init?(_ word: String) {
        let lowerA = UInt8(ascii: "a")
        let lowerZ = UInt8(ascii: "z")
        let lowerE = UInt8(ascii: "e")
        var accentedE: Int?

        for character in word {
            if let ascii = character.asciiValue {
                if ascii >= lowerA && ascii <= lowerZ {
                    letters.append(ascii)
                }
                continue
            }
            if let replacement = Self.replacements[character] {
                letters.append(contentsOf: replacement.utf8)
                continue
            }
            // Accented letters decompose into a base letter and combining marks.
            let scalars = Array(String(character).decomposedStringWithCanonicalMapping.unicodeScalars)
            guard let base = scalars.first, base.isASCII else { continue }
            let value = UInt8(base.value)
            guard value >= lowerA && value <= lowerZ else { continue }
            let marks = scalars.dropFirst().map(\.value)
            if marks.contains(0x0308), let previous = letters.last, EnglishSpelling.isVowelLetter(previous) {
                forcedSplits.insert(letters.count)
            }
            if value == lowerE && (marks.contains(0x0301) || marks.contains(0x0308)) {
                accentedE = letters.count
            }
            letters.append(value)
        }

        guard !letters.isEmpty else { return nil }
        if let accentedE {
            let endsWithS = letters.last == UInt8(ascii: "s")
            stressedFinalE = accentedE == letters.count - 1 || (endsWithS && accentedE == letters.count - 2)
        }
    }
}
