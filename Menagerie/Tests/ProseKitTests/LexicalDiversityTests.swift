import XCTest
@testable import ProseKit

final class LexicalDiversityTests: XCTestCase {
    func testTypeTokenRatioAndHapaxes() {
        let diversity = LexicalDiversity(words: ["a", "b", "a", "c"])
        XCTAssertEqual(diversity.tokenCount, 4)
        XCTAssertEqual(diversity.typeCount, 3)
        XCTAssertEqual(diversity.hapaxCount, 2)
        XCTAssertEqual(diversity.typeTokenRatio, 0.75, accuracy: 1e-12)
    }

    /// a b a | b a b: the running ratio hits 2/3 ≤ 0.72 after every third
    /// word, so each pass finds exactly two factors in six words.
    func testMTLDCountsFullFactors() throws {
        let mtld = try XCTUnwrap(LexicalDiversity.mtld(of: ["a", "b", "a", "b", "a", "b"]))
        XCTAssertEqual(mtld, 3, accuracy: 1e-12)
    }

    /// a b c a never reaches the threshold (its ratio bottoms out at 0.75),
    /// so the pass is one partial factor: (1 − 0.75) / (1 − 0.72).
    func testMTLDCountsPartialFactors() throws {
        let mtld = try XCTUnwrap(LexicalDiversity.mtld(of: ["a", "b", "c", "a"]))
        XCTAssertEqual(mtld, 4 / ((1 - 0.75) / (1 - 0.72)), accuracy: 1e-12)
    }

    func testMTLDIsUndefinedWhenNothingRepeats() {
        XCTAssertNil(LexicalDiversity.mtld(of: ["every", "word", "is", "new"]))
        XCTAssertNil(LexicalDiversity.mtld(of: []))
    }

    func testRicherVocabularyScoresHigher() throws {
        let repetitive = Array(repeating: ["the", "cat", "sat", "on", "the", "mat"], count: 10).flatMap { $0 }
        let varied = """
            a quick brown fox jumps over the lazy dog while seven wizards quietly hex jolly \
            farmers who grumble about vexing weather patterns and dwindling harvests across \
            misty northern valleys where ancient rivers carve through the stubborn granite
            """.split(separator: " ").map(String.init)
        let low = try XCTUnwrap(LexicalDiversity.mtld(of: repetitive))
        let high = try XCTUnwrap(LexicalDiversity.mtld(of: varied))
        XCTAssertGreaterThan(high, low * 5)
        XCTAssertLessThan(LexicalDiversity(words: repetitive).typeTokenRatio, LexicalDiversity(words: varied).typeTokenRatio)
    }

    func testEmpty() {
        let diversity = LexicalDiversity(words: [])
        XCTAssertEqual(diversity.tokenCount, 0)
        XCTAssertEqual(diversity.typeTokenRatio, 0)
        XCTAssertNil(diversity.mtld)
    }
}
