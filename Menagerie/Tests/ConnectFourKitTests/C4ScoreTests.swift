import XCTest
@testable import ConnectFourKit

final class C4ScoreTests: XCTestCase {
    func testScoresOrderFromWorstToBest() {
        let ordered: [C4Score] = [
            .loss(inMoves: 1),
            .loss(inMoves: 6),
            .estimate(-40),
            .estimate(0),
            .draw,
            .estimate(3),
            .win(inMoves: 9),
            .win(inMoves: 2),
            .win(inMoves: 1),
        ]
        for (worse, better) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(worse, better)
            XCTAssertGreaterThan(better, worse)
        }
        var generator = C4SplitMix64(seed: 3)
        XCTAssertEqual(ordered.shuffled(using: &generator).sorted(), ordered)
    }

    func testRawValuesBecomeMoveCounts() {
        let win = C4Searcher.win
        // With 10 discs down, the 11th disc is this move and the 12th is the
        // opponent's reply.
        XCTAssertEqual(C4Score(raw: win - 11, discs: 10, isExact: false), .win(inMoves: 1))
        XCTAssertEqual(C4Score(raw: win - 13, discs: 10, isExact: false), .win(inMoves: 2))
        XCTAssertEqual(C4Score(raw: -(win - 12), discs: 10, isExact: false), .loss(inMoves: 1))
        XCTAssertEqual(C4Score(raw: -(win - 14), discs: 10, isExact: false), .loss(inMoves: 2))
        XCTAssertEqual(C4Score(raw: 0, discs: 10, isExact: true), .draw)
        XCTAssertEqual(C4Score(raw: 0, discs: 10, isExact: false), .estimate(0))
        XCTAssertEqual(C4Score(raw: -17, discs: 10, isExact: true), .estimate(-17))
    }

    func testNormalizedValuesFitTheBars() {
        XCTAssertEqual(C4Score.win(inMoves: 1).normalized, 1)
        XCTAssertEqual(C4Score.loss(inMoves: 1).normalized, -1)
        XCTAssertEqual(C4Score.draw.normalized, 0)
        XCTAssertGreaterThan(C4Score.win(inMoves: 2).normalized, C4Score.win(inMoves: 8).normalized)
        XCTAssertGreaterThanOrEqual(C4Score.win(inMoves: 21).normalized, 0.8)
        for value in stride(from: -500, through: 500, by: 7) {
            let normalized = C4Score.estimate(value).normalized
            XCTAssertLessThanOrEqual(abs(normalized), 0.75)
            XCTAssertEqual(normalized.sign == .minus, value < 0, "Sign of \(value)")
        }
    }

    func testDescriptions() {
        XCTAssertEqual(C4Score.win(inMoves: 3).description, "Win in 3")
        XCTAssertEqual(C4Score.loss(inMoves: 2).description, "Loss in 2")
        XCTAssertEqual(C4Score.draw.description, "Draw")
        XCTAssertEqual(C4Score.estimate(5).description, "+5")
        XCTAssertEqual(C4Score.estimate(-4).description, "-4")
        XCTAssertEqual(C4Score.estimate(0).description, "0")
    }
}
