import XCTest
@testable import ProseKit

final class ProseTokenizerTests: XCTestCase {
    // MARK: - Words

    func testWordsKeepApostrophesAndHyphensInside() {
        XCTAssertEqual(words("Don't stop\u{2014}it\u{2019}s state-of-the-art!"), ["Don't", "stop", "it\u{2019}s", "state-of-the-art"])
    }

    func testNumbersKeepTheirSeparators() {
        XCTAssertEqual(words("It costs $1,024.50, or 3.5% more."), ["It", "costs", "1,024.50", "or", "3.5", "more"])
    }

    func testDottedAbbreviationsAreOneWord() {
        XCTAssertEqual(words("The U.S. and e.g. rules"), ["The", "U.S.", "and", "e.g.", "rules"])
    }

    func testWordRangesPointBackIntoTheText() {
        let text = "Caf\u{00E9} owners\u{2014}\u{201C}naïve\u{201D} ones\u{2014}smile 😊 a lot."
        let found = ProseTokenizer.words(in: text)
        XCTAssertEqual(found.map(\.text), ["Café", "owners", "naïve", "ones", "smile", "a", "lot"])
        for word in found {
            XCTAssertEqual(String(text[word.range]), word.text)
        }
    }

    func testWordProperties() {
        let found = ProseTokenizer.words(in: "Well-known 1990 Paris It\u{2019}s")
        XCTAssertTrue(found[0].isHyphenated)
        XCTAssertTrue(found[1].isNumeric)
        XCTAssertTrue(found[2].isCapitalized)
        XCTAssertEqual(found[3].normalized, "it's")
    }

    func testWordsWithinARange() {
        let text = "One two. Three four."
        let second = ProseTokenizer.sentences(in: text)[1]
        XCTAssertEqual(ProseTokenizer.words(in: text, within: second.range).map(\.text), ["Three", "four"])
    }

    // MARK: - Sentences

    func testSentencesSplitAtTerminalPunctuation() {
        XCTAssertEqual(sentences("Hello there. How are you? Fine!"), ["Hello there.", "How are you?", "Fine!"])
    }

    func testTitlesAndAbbreviationsDoNotEndSentences() {
        XCTAssertEqual(
            sentences("Dr. Smith met Mr. Jones at 5 p.m. on Friday. They talked about the U.S. Army. It was long."),
            ["Dr. Smith met Mr. Jones at 5 p.m. on Friday.", "They talked about the U.S. Army.", "It was long."]
        )
    }

    func testAnAbbreviationCanStillEndASentence() {
        XCTAssertEqual(
            sentences("She moved to the U.S. The weather was better. He joined Acme Inc. Then he left."),
            ["She moved to the U.S.", "The weather was better.", "He joined Acme Inc.", "Then he left."]
        )
    }

    func testInitialsDoNotEndSentences() {
        XCTAssertEqual(sentences("J. K. Rowling wrote it. Then she rested."), ["J. K. Rowling wrote it.", "Then she rested."])
    }

    func testDecimalsAndDomainsDoNotEndSentences() {
        XCTAssertEqual(sentences("Pi is 3.14 today. Visit example.com now."), ["Pi is 3.14 today.", "Visit example.com now."])
    }

    func testClosingQuotesStayWithTheirSentence() {
        XCTAssertEqual(
            sentences("\u{201C}Stop!\u{201D} she said. He did. \u{201C}Good.\u{201D} Then silence."),
            ["\u{201C}Stop!\u{201D} she said.", "He did.", "\u{201C}Good.\u{201D}", "Then silence."]
        )
    }

    func testLowercaseAfterPunctuationContinuesTheSentence() {
        XCTAssertEqual(sentences("Wait... what happened? Nothing. I waited... Then it rang."), [
            "Wait... what happened?", "Nothing.", "I waited...", "Then it rang.",
        ])
    }

    func testIdeographicPunctuationEndsSentencesWithoutSpaces() {
        XCTAssertEqual(sentences("東京は大きい。大阪も大きい！本当？"), ["東京は大きい。", "大阪も大きい！", "本当？"])
    }

    func testLineBreaks() {
        XCTAssertEqual(sentences("Title\nThe body starts here. More text."), ["Title", "The body starts here.", "More text."])
        XCTAssertEqual(sentences("This sentence is\nwrapped across lines."), ["This sentence is\nwrapped across lines."])
        XCTAssertEqual(sentences("first paragraph\n\nsecond paragraph"), ["first paragraph", "second paragraph"])
    }

    func testSentenceRangesExcludeSurroundingWhitespace() {
        let text = "  One.   Two words.  "
        let found = ProseTokenizer.sentences(in: text)
        XCTAssertEqual(found.map { String(text[$0.range]) }, ["One.", "Two words."])
    }

    func testEdgeCases() {
        XCTAssertEqual(sentences(""), [])
        XCTAssertEqual(sentences("   \n\n  "), [])
        XCTAssertEqual(sentences("* * *"), [], "Stretches without letters or digits are skipped")
        XCTAssertEqual(sentences("no punctuation here"), ["no punctuation here"])
        XCTAssertEqual(words(""), [])
        XCTAssertEqual(words("Hello"), ["Hello"])
    }

    private func words(_ text: String) -> [String] {
        ProseTokenizer.words(in: text).map(\.text)
    }

    private func sentences(_ text: String) -> [String] {
        ProseTokenizer.sentences(in: text).map(\.text)
    }
}
