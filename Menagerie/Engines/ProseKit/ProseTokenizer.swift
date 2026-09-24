import Foundation

/// A word found in a text by `ProseTokenizer`.
///
/// A word is a run of letters and digits. Apostrophes and hyphens join the
/// pieces of one word ("don't", "state-of-the-art"), as do periods and commas
/// between digits ("3.14", "1,024") and the periods of dotted abbreviations
/// ("U.S.", "e.g.").
public struct ProseWord: Hashable, Sendable {
    /// The word exactly as written.
    public let text: String
    /// Where the word sits in the text it was read from.
    public let range: Range<String.Index>

    public init(text: String, range: Range<String.Index>) {
        self.text = text
        self.range = range
    }

    /// The form used for counting and matching: lowercased, with curly
    /// apostrophes straightened.
    public var normalized: String {
        ProseTokenizer.normalize(text)
    }

    /// True when the word has no letters, like "1990" or "3.5".
    public var isNumeric: Bool {
        !text.contains(where: \.isLetter)
    }

    /// True when the word's first letter is uppercase.
    public var isCapitalized: Bool {
        text.first(where: \.isLetter)?.isUppercase ?? false
    }

    /// True for compounds such as "well-known".
    public var isHyphenated: Bool {
        text.contains(where: ProseTokenizer.isHyphen)
    }
}

/// A sentence found in a text by `ProseTokenizer`, without its surrounding
/// whitespace.
public struct ProseSentence: Hashable, Sendable {
    /// The sentence exactly as written, terminal punctuation included.
    public let text: String
    /// Where the sentence sits in the text it was read from.
    public let range: Range<String.Index>

    public init(text: String, range: Range<String.Index>) {
        self.text = text
        self.range = range
    }
}

/// Splits prose into words and sentences.
///
/// The rules are written for English but hold up in most languages that
/// separate words with spaces. Sentences also end at the ideographic
/// punctuation of Chinese and Japanese ("。", "！", "？"), which needs no
/// space after it.
public enum ProseTokenizer {
    /// Every word in `text`, in order.
    public static func words(in text: String) -> [ProseWord] {
        words(in: text, within: text.startIndex..<text.endIndex)
    }

    /// The words that lie inside `bounds`, a range of `text`.
    public static func words(in text: String, within bounds: Range<String.Index>) -> [ProseWord] {
        let characters = Array(text[bounds])
        let indices = Array(text[bounds].indices) + [bounds.upperBound]
        var words: [ProseWord] = []
        var position = 0

        while position < characters.count {
            guard isWordCharacter(characters[position]) else {
                position += 1
                continue
            }
            let start = position
            var end = position + 1
            while end < characters.count {
                if isWordCharacter(characters[end]) {
                    end += 1
                } else if end + 1 < characters.count,
                          joins(characters, at: end, wordStart: start) {
                    end += 2
                } else {
                    break
                }
            }
            // A dotted abbreviation keeps its final period: "U.S.", "e.g.".
            if end < characters.count, characters[end] == ".",
               isDottedAbbreviation(characters[start..<end]) {
                end += 1
            }
            let range = indices[start]..<indices[end]
            words.append(ProseWord(text: String(text[range]), range: range))
            position = end
        }
        return words
    }

    /// The sentences of `text`, in order. Stretches of text with no letters
    /// or digits, such as a lone "* * *", are skipped.
    public static func sentences(in text: String) -> [ProseSentence] {
        let characters = Array(text)
        let indices = Array(text.indices) + [text.endIndex]
        var sentences: [ProseSentence] = []
        var start: Int?

        func close(at end: Int) {
            guard let first = start else { return }
            start = nil
            var last = end
            while last > first, characters[last - 1].isWhitespace {
                last -= 1
            }
            guard characters[first..<last].contains(where: { $0.isLetter || $0.isNumber }) else { return }
            let range = indices[first]..<indices[last]
            sentences.append(ProseSentence(text: String(text[range]), range: range))
        }

        var position = 0
        while position < characters.count {
            let character = characters[position]
            if start == nil {
                if character.isWhitespace {
                    position += 1
                    continue
                }
                start = position
            }

            if character.isNewline {
                // A blank line always ends a sentence. A single line break ends
                // one unless the next line carries on in lowercase, as
                // hard-wrapped prose does.
                var next = position
                var lineBreaks = 0
                while next < characters.count, characters[next].isWhitespace {
                    if characters[next].isNewline { lineBreaks += 1 }
                    next += 1
                }
                if lineBreaks >= 2 || next == characters.count || !characters[next].isLowercase {
                    close(at: position)
                }
                position = next
                continue
            }

            if isTerminator(character) {
                var clusterEnd = position + 1
                while clusterEnd < characters.count,
                      isTerminator(characters[clusterEnd]) || isCloser(characters[clusterEnd]) {
                    clusterEnd += 1
                }
                if endsSentence(characters, terminator: position, clusterEnd: clusterEnd) {
                    close(at: clusterEnd)
                }
                position = clusterEnd
                continue
            }
            position += 1
        }
        close(at: characters.count)
        return sentences
    }

    /// Abbreviations that can end a sentence but usually don't, written in
    /// lowercase without their final period. A period after one ends the
    /// sentence only when a typical sentence opener follows.
    public static let abbreviations: Set<String> = [
        "a.m", "p.m", "u.s", "u.k", "u.n", "e.u", "u.s.a", "d.c", "ph.d", "b.a", "m.a", "m.d",
        "e.g", "i.e", "etc", "vs", "cf", "al", "approx", "est", "misc", "no", "nos", "fig", "figs",
        "vol", "vols", "ed", "eds", "pp", "p", "inc", "ltd", "co", "corp", "llc", "plc", "bros",
        "dept", "univ", "assn", "intl", "natl", "govt", "ave", "blvd", "rd", "hwy",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun", "jr", "sr",
    ]

    /// Titles that come before a name and so never end a sentence.
    public static let titleAbbreviations: Set<String> = [
        "mr", "mrs", "ms", "mx", "dr", "prof", "st", "rev", "hon", "gen", "gov", "sen", "rep",
        "lt", "col", "capt", "sgt", "cpl", "pvt", "maj", "adm", "cmdr", "fr", "mt", "ft",
        "messrs", "mme", "mlle", "pres", "supt", "insp", "det",
    ]

    // MARK: - Characters

    static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BC}"]

    static func isHyphen(_ character: Character) -> Bool {
        character == "-" || character == "\u{2010}" || character == "\u{2011}"
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Lowercases a word and straightens its apostrophes.
    static func normalize(_ word: some StringProtocol) -> String {
        var result = word.lowercased()
        if result.contains("\u{2019}") || result.contains("\u{02BC}") {
            result = result
                .replacingOccurrences(of: "\u{2019}", with: "'")
                .replacingOccurrences(of: "\u{02BC}", with: "'")
        }
        return result
    }

    /// Whether the character at `index` glues the word on its left to the
    /// word character on its right.
    private static func joins(_ characters: [Character], at index: Int, wordStart: Int) -> Bool {
        let joiner = characters[index]
        let before = characters[index - 1]
        let after = characters[index + 1]
        guard isWordCharacter(after) else { return false }
        if apostrophes.contains(joiner) || isHyphen(joiner) {
            return true
        }
        if joiner == "." || joiner == "," {
            if before.isNumber && after.isNumber { return true }
            // Dotted abbreviations are single letters between periods.
            if joiner == ".", before.isLetter, after.isLetter {
                let segmentStart = characters[wordStart..<index].lastIndex(of: ".").map { $0 + 1 } ?? wordStart
                return index - segmentStart == 1
            }
        }
        return false
    }

    private static func isDottedAbbreviation(_ word: ArraySlice<Character>) -> Bool {
        guard word.contains(".") else { return false }
        return word.split(separator: ".").allSatisfy { $0.count == 1 && $0.allSatisfy(\.isLetter) }
    }

    private static let latinTerminators: Set<Character> = [
        ".", "!", "?", "\u{2026}", "\u{203C}", "\u{2047}", "\u{2048}", "\u{2049}",
        "\u{0964}", "\u{0965}", "\u{061F}", "\u{06D4}",
    ]

    /// Ideographic sentence punctuation, which needs no space after it.
    private static let ideographicTerminators: Set<Character> = [
        "\u{3002}", "\u{FF01}", "\u{FF1F}", "\u{FF0E}", "\u{FF61}",
    ]

    private static let closers: Set<Character> = [
        "\"", "'", "\u{201D}", "\u{2019}", "\u{00BB}", "\u{203A}", ")", "]", "}",
        "\u{300D}", "\u{300F}", "\u{FF09}", "\u{3011}", "\u{3015}", "\u{3009}", "\u{300B}",
    ]

    private static func isTerminator(_ character: Character) -> Bool {
        latinTerminators.contains(character) || ideographicTerminators.contains(character)
    }

    private static func isCloser(_ character: Character) -> Bool {
        closers.contains(character)
    }

    /// Words that typically open a sentence, used to decide whether a period
    /// after an abbreviation or an initial also ends the sentence.
    private static let sentenceOpeners: Set<String> = [
        "the", "a", "an", "it", "its", "this", "that", "these", "those", "he", "she", "they", "we",
        "i", "you", "his", "her", "their", "our", "my", "your", "but", "and", "or", "so", "yet",
        "in", "on", "at", "for", "with", "after", "before", "when", "while", "if", "as", "there",
        "here", "then", "however", "meanwhile", "still", "also", "some", "many", "most", "no",
        "not", "what", "why", "how", "where", "who", "which", "one", "both", "each", "every",
    ]

    // MARK: - Sentence boundaries

    /// Decides whether the terminal punctuation at `terminator`, followed by
    /// more terminal punctuation and closing quotes up to `clusterEnd`, ends a
    /// sentence.
    private static func endsSentence(_ characters: [Character], terminator: Int, clusterEnd: Int) -> Bool {
        let mark = characters[terminator]
        if ideographicTerminators.contains(mark) { return true }

        // "3.14", "example.com" and "U.S.-based" continue without a space.
        if clusterEnd < characters.count, !characters[clusterEnd].isWhitespace { return false }

        var next = clusterEnd
        while next < characters.count, characters[next].isWhitespace {
            next += 1
        }
        guard next < characters.count else { return true }
        // "e.g. the", "Wait... what?" and "Stop!" he said: the sentence goes on.
        if characters[next].isLowercase { return false }

        // Only a single period can belong to an abbreviation or an initial.
        let isSinglePeriod = mark == "."
            && characters[(terminator + 1)..<clusterEnd].allSatisfy { !isTerminator($0) }
        guard isSinglePeriod else { return true }

        var wordStart = terminator
        while wordStart > 0, characters[wordStart - 1].isLetter || characters[wordStart - 1] == "." {
            wordStart -= 1
        }
        let word = String(characters[wordStart..<terminator])
        let key = word.lowercased()
        if titleAbbreviations.contains(key) { return false }

        let isInitial = word.count == 1 && word.first?.isUppercase == true
        if isInitial || abbreviations.contains(key) {
            return opensSentence(characters, at: next)
        }
        return true
    }

    private static func opensSentence(_ characters: [Character], at index: Int) -> Bool {
        let first = characters[index]
        if isCloser(first) || first == "\u{201C}" || first == "\u{2018}" { return true }
        var end = index
        while end < characters.count, characters[end].isLetter {
            end += 1
        }
        guard end > index else { return false }
        return sentenceOpeners.contains(String(characters[index..<end]).lowercased())
    }
}
