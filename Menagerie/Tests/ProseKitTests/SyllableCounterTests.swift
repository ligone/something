import XCTest
@testable import ProseKit

final class SyllableCounterTests: XCTestCase {
    private let counter = SyllableCounter.english

    /// Dictionary syllable counts, each confirmed against the CMU Pronouncing
    /// Dictionary, chosen to exercise every rule the counter implements.
    ///
    /// Tolerance: a spelling heuristic can't match a dictionary everywhere,
    /// so at least 95% of these must be exact, and none may be off by more
    /// than one syllable.
    private static let dictionaryCounts: [(word: String, syllables: Int)] = [
        ("the", 1), ("cat", 1), ("strength", 1), ("through", 1), ("queue", 1),
        ("make", 1), ("whale", 1), ("aisle", 1), ("eyes", 1), ("jumped", 1),
        ("walked", 1), ("played", 1), ("stayed", 1), ("makes", 1), ("league", 1),
        ("table", 2), ("little", 2), ("acre", 2), ("tables", 2), ("handled", 2),
        ("hundred", 2), ("wanted", 2), ("needed", 2), ("boxes", 2), ("naked", 2),
        ("player", 2), ("lawyer", 2), ("canyon", 2), ("flying", 2), ("beyond", 2),
        ("goodbye", 2), ("going", 2), ("being", 2), ("lion", 2), ("poem", 2),
        ("quiet", 2), ("diet", 2), ("cruel", 2), ("create", 2), ("chaos", 2),
        ("rhythm", 2), ("prism", 2), ("people", 2), ("business", 2), ("science", 2),
        ("ancient", 2), ("nation", 2), ("vision", 2), ("special", 2), ("unique", 2),
        ("hopeless", 2), ("careful", 2), ("lonely", 2), ("movement", 2), ("statement", 2),
        ("something", 2), ("homework", 2), ("lifestyle", 2), ("eighteen", 2), ("water", 2),
        ("apple", 2), ("orange", 2), ("idea", 3), ("area", 3), ("created", 3),
        ("video", 3), ("radio", 3), ("piano", 3), ("museum", 3), ("actual", 3),
        ("heroic", 3), ("musician", 3), ("genuine", 3), ("dialogue", 3), ("recipe", 3),
        ("family", 3), ("beautiful", 3), ("happiness", 3), ("wonderful", 3), ("everything", 3),
        ("poetry", 3), ("syllable", 3), ("copying", 3), ("computer", 3), ("elephant", 3),
        ("banana", 3), ("photograph", 3), ("tomorrow", 3), ("especially", 4), ("usually", 4),
        ("temperature", 4), ("dictionary", 4), ("society", 4), ("reality", 4), ("biology", 4),
        ("appreciate", 4), ("coordinate", 4), ("readability", 5), ("university", 5),
        ("international", 5), ("communication", 5),
    ]

    func testCountsMatchTheDictionaryWithinTolerance() {
        var misses: [String] = []
        for (word, expected) in Self.dictionaryCounts {
            let counted = counter.syllables(in: word)
            XCTAssertLessThanOrEqual(abs(counted - expected), 1, "\(word): counted \(counted), dictionary \(expected)")
            if counted != expected {
                misses.append("\(word) (\(counted) vs \(expected))")
            }
        }
        let accuracy = 1 - Double(misses.count) / Double(Self.dictionaryCounts.count)
        XCTAssertGreaterThanOrEqual(accuracy, 0.95, "Misses: \(misses.joined(separator: ", "))")
    }

    func testSilentFinalE() {
        assertSyllables(["make": 1, "hope": 1, "shoe": 1, "the": 1, "be": 1, "free": 1])
    }

    func testConsonantPlusLeOrReKeepsItsSyllable() {
        assertSyllables(["table": 2, "little": 2, "castle": 2, "acre": 2, "centre": 2, "whale": 1, "more": 1, "style": 1])
    }

    func testEdAndEsEndings() {
        assertSyllables([
            "jumped": 1, "moved": 1, "wanted": 2, "needed": 2, "handled": 2, "sacred": 2,
            "boxes": 2, "places": 2, "wishes": 2, "judges": 2, "makes": 1, "times": 1, "tables": 2,
        ])
    }

    func testYIsSometimesAVowel() {
        assertSyllables([
            "yes": 1, "gym": 1, "happy": 2, "player": 2, "flyer": 2, "dryer": 2,
            "canyon": 2, "copying": 3, "studying": 3, "goodbye": 2, "eyes": 1, "types": 1,
        ])
    }

    func testVowelPairsThatSpanTwoSyllables() {
        assertSyllables([
            "lion": 2, "create": 2, "creature": 2, "being": 2, "video": 3, "actual": 3,
            "language": 2, "quiet": 2, "idea": 3, "poem": 2, "fluid": 2, "museum": 3,
            "nation": 2, "social": 2, "Italian": 3, "million": 2, "happier": 3, "sociology": 5,
        ])
    }

    func testSuffixesAndCompoundsHideSilentE() {
        assertSyllables([
            "hopeless": 2, "lovely": 2, "lately": 2, "happiness": 3, "careful": 2, "beautiful": 3,
            "something": 2, "someone": 2, "everybody": 4, "homework": 2, "baseball": 2,
            "timeline": 2, "statement": 2, "supposedly": 4,
        ])
    }

    func testSyllabicConsonants() {
        assertSyllables(["prism": 2, "sarcasm": 3, "rhythm": 2, "algorithms": 4])
    }

    func testLexiconExceptions() {
        assertSyllables(["business": 2, "recipe": 3, "naked": 2, "aisle": 1, "colonel": 2])
        let custom = SyllableCounter(additionalExceptions: ["Gif": 1, "business": 3])
        XCTAssertEqual(custom.syllables(in: "gif"), 1)
        XCTAssertEqual(custom.syllables(in: "business"), 3, "Additional exceptions override built-in ones")
    }

    func testNumbersAreReadAloud() {
        assertSyllables([
            "7": 2, "12": 1, "100": 3, "1,250": 8, "3.14": 4, "1984": 5, "1905": 4,
            "2024": 5, "2008": 4, "1990s": 4, "21st": 3,
        ])
    }

    func testAcronymsAndAbbreviations() {
        assertSyllables(["BBC": 3, "FBI": 3, "US": 2, "HTML": 4, "WWW": 9, "NASA": 2, "U.S.": 2, "e.g.": 2, "MP3": 3])
        XCTAssertEqual(counter.syllables(in: "THE"), 1, "Shouted function words are not acronyms")
    }

    func testContractions() {
        assertSyllables([
            "don't": 1, "didn't": 2, "couldn't": 2, "isn't": 2, "should've": 2, "it'll": 2,
            "it's": 1, "you're": 1, "we'll": 1, "James's": 2, "Delgado\u{2019}s": 3,
        ])
    }

    func testHyphenatedWordsAddUpTheirParts() {
        assertSyllables(["well-known": 2, "state-of-the-art": 4, "e-mail": 2])
    }

    func testAccentsAndOtherScripts() {
        assertSyllables(["café": 2, "passé": 2, "résumé": 3, "naïve": 2, "Brontë": 2, "Zürich": 2])
        XCTAssertEqual(counter.syllables(in: "東京"), 1, "Words in other scripts count as one syllable")
        XCTAssertEqual(counter.syllables(in: "Москва"), 1)
    }

    func testCaseDoesNotMatter() {
        XCTAssertEqual(counter.syllables(in: "Beautiful"), 3)
        XCTAssertEqual(counter.syllables(in: "BEAUTIFUL"), 3)
    }

    func testEmptyAndPunctuationOnly() {
        assertSyllables(["": 0, "...": 0, "\u{2014}": 0, "'": 0, "\u{00BD}": 0])
    }

    private func assertSyllables(_ expectations: [String: Int], file: StaticString = #filePath, line: UInt = #line) {
        for (word, expected) in expectations.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(counter.syllables(in: word), expected, "\"\(word)\"", file: file, line: line)
        }
    }
}
