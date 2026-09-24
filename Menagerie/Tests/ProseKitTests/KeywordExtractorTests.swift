import XCTest
@testable import ProseKit

final class KeywordExtractorTests: XCTestCase {
    /// The abstract RAKE's authors used to introduce the method (Rose et al.,
    /// 2010, figure 1.1).
    private let abstract = """
        Compatibility of systems of linear constraints over the set of natural numbers. \
        Criteria of compatibility of a system of linear Diophantine equations, strict \
        inequations, and nonstrict inequations are considered. Upper bounds for components \
        of a minimal set of solutions and algorithms of construction of minimal generating \
        sets of solutions for all types of systems are given. These criteria and the \
        corresponding algorithms for constructing a minimal supporting set of solutions can \
        be used in solving all the considered types of systems and systems of mixed types.
        """

    func testRanksThePapersTopKeywordsFirst() {
        let phrases = KeywordExtractor().keyphrases(in: abstract)
        XCTAssertEqual(Array(phrases.prefix(3).map(\.normalized)), [
            "minimal generating sets",
            "linear diophantine equations",
            "minimal supporting set",
        ])
    }

    /// Degree-to-frequency scores match table 1.1 of the paper.
    func testScoresMatchThePaper() {
        let scores = Dictionary(uniqueKeysWithValues: KeywordExtractor().keyphrases(in: abstract).map { ($0.normalized, $0.score) })
        let expected: [String: Double] = [
            "minimal generating sets": 8 / 3.0 + 3 + 3,
            "linear diophantine equations": 2.5 + 3 + 3,
            "minimal supporting set": 8 / 3.0 + 3 + 2,
            "minimal set": 8 / 3.0 + 2,
            "linear constraints": 2.5 + 2,
            "natural numbers": 4,
            "strict inequations": 4,
            "upper bounds": 4,
            "mixed types": 2 + 5 / 3.0,
            "corresponding algorithms": 2 + 1.5,
            "considered types": 1.5 + 5 / 3.0,
            "systems": 1,
        ]
        for (phrase, score) in expected {
            XCTAssertEqual(scores[phrase] ?? -1, score, accuracy: 1e-9, phrase)
        }
    }

    func testOccurrencesPointBackIntoTheText() throws {
        let phrases = KeywordExtractor().keyphrases(in: abstract)
        let systems = try XCTUnwrap(phrases.first { $0.normalized == "systems" })
        XCTAssertEqual(systems.frequency, 4)
        for phrase in phrases {
            XCTAssertEqual(phrase.occurrences.count, phrase.frequency)
            for range in phrase.occurrences {
                let words = ProseTokenizer.words(in: String(abstract[range])).map { KeywordExtractor.key(for: $0) }
                XCTAssertEqual(words, phrase.words)
            }
        }
    }

    func testStopwordsNumbersAndPunctuationSeparatePhrases() {
        let phrases = KeywordExtractor().keyphrases(in: "Fast cars, slow boats and the open sea. In 2024 the agency\u{2019}s new satellite launched.")
        XCTAssertEqual(Set(phrases.map(\.normalized)), ["fast cars", "slow boats", "open sea", "agency new satellite launched"])
        let satellite = phrases.first { $0.words.contains("satellite") }
        XCTAssertEqual(satellite?.text, "agency\u{2019}s new satellite launched", "Display text keeps the original spelling")
    }

    func testLongCandidatesAreDropped() {
        let text = "Brave little yellow ducklings swam happily. Quiet ponds sparkle."
        XCTAssertEqual(KeywordExtractor().keyphrases(in: text).map(\.normalized), ["quiet ponds sparkle"])
        XCTAssertEqual(
            KeywordExtractor(maximumPhraseLength: 6).keyphrases(in: text).map(\.normalized),
            ["brave little yellow ducklings swam happily", "quiet ponds sparkle"]
        )
    }

    func testAdjoiningKeywordsNeedToRepeat() throws {
        let text = "We studied the axis of evil. Critics debated the axis of evil. The axis of power shifted."
        let joined = KeywordExtractor().keyphrases(in: text)
        let axisOfEvil = try XCTUnwrap(joined.first { $0.normalized == "axis of evil" })
        XCTAssertEqual(axisOfEvil.frequency, 2)
        // "axis" scores 3/3 = 1 and "evil" 2/2 = 1.
        XCTAssertEqual(axisOfEvil.score, 2, accuracy: 1e-9)
        XCTAssertNil(joined.first { $0.normalized == "axis of power shifted" }, "A combination seen once is not a keyword")

        let plain = KeywordExtractor(joinsAdjoiningKeywords: false).keyphrases(in: text)
        XCTAssertNil(plain.first { $0.normalized == "axis of evil" })
    }

    func testTiesGoToTheMoreFrequentThenTheEarlierPhrase() {
        let phrases = KeywordExtractor().keyphrases(in: "Rivers flow. Mountains rise. Rivers flow.")
        XCTAssertEqual(phrases.map(\.normalized), ["rivers flow", "mountains rise"])
    }

    func testEdgeCases() {
        XCTAssertEqual(KeywordExtractor().keyphrases(in: ""), [])
        XCTAssertEqual(KeywordExtractor().keyphrases(in: "the and of it"), [])
        let single = KeywordExtractor().keyphrases(in: "Hello")
        XCTAssertEqual(single.map(\.text), ["Hello"])
        XCTAssertEqual(single.first?.score, 1)
    }
}
