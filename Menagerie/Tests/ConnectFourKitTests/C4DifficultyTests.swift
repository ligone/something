import XCTest
import ConnectFourKit

final class C4DifficultyTests: XCTestCase {
    private let engine = C4Engine(tableSize: 1 << 18)

    func testEveryLevelTakesAWinOnTheSpot() {
        let analysis = engine.analyze(C4Board.position("112233"), limits: C4SearchLimits(maxDepth: 4))
        for level in C4Difficulty.allCases {
            for seed in 0..<20 {
                var generator = C4SplitMix64(seed: UInt64(seed))
                XCTAssertEqual(level.chooseColumn(from: analysis, using: &generator), 3, "\(level)")
            }
        }
    }

    func testEveryLevelBlocksAnImmediateThreat() {
        let analysis = engine.analyze(C4Board.position("11223"), limits: C4SearchLimits(maxDepth: 4))
        for level in C4Difficulty.allCases {
            for seed in 0..<20 {
                var generator = C4SplitMix64(seed: UInt64(seed))
                XCTAssertEqual(level.chooseColumn(from: analysis, using: &generator), 3, "\(level)")
            }
        }
    }

    func testCasualPlayVariesButRepeatsWithTheSameSeed() {
        let analysis = engine.analyze(C4Board(), limits: C4SearchLimits(maxDepth: 4))
        func choices(seed: UInt64) -> [Int] {
            var generator = C4SplitMix64(seed: seed)
            return (0..<40).compactMap { _ in C4Difficulty.casual.chooseColumn(from: analysis, using: &generator) }
        }
        XCTAssertEqual(choices(seed: 7), choices(seed: 7))
        XCTAssertGreaterThan(Set(choices(seed: 7)).count, 1, "Casual play should not be deterministic")
        XCTAssertEqual(
            C4Difficulty.ruthless.chooseColumn(from: analysis),
            analysis.bestColumn,
            "Ruthless always plays the best move"
        )
    }

    func testLevelsSearchProgressivelyHarder() {
        let levels = C4Difficulty.allCases.map(\.limits)
        XCTAssertLessThan(levels[0].maxDepth, levels[1].maxDepth)
        XCTAssertLessThan(levels[1].maxDepth, levels[2].maxDepth)
        XCTAssertLessThan(levels[0].timeBudget!, levels[1].timeBudget!)
        XCTAssertLessThan(levels[1].timeBudget!, levels[2].timeBudget!)
    }

    func testDeeperSearchBeatsCasualPlay() throws {
        // Depth limits only, so the games do not depend on machine speed.
        let casual = C4SearchLimits(maxDepth: C4Difficulty.casual.limits.maxDepth)
        let deeper = C4SearchLimits(maxDepth: 8)
        var generator = C4SplitMix64(seed: 61)
        var deeperWins = 0
        for gameIndex in 0..<6 {
            var game = C4Game()
            let deeperSide: C4Player = gameIndex % 2 == 0 ? .first : .second
            while !game.isOver {
                let isDeeper = game.playerToMove == deeperSide
                let analysis = engine.analyze(game.board, limits: isDeeper ? deeper : casual)
                let level: C4Difficulty = isDeeper ? .strong : .casual
                let choice = level.chooseColumn(from: analysis, using: &generator)
                try game.play(try XCTUnwrap(choice))
            }
            XCTAssertNotEqual(game.outcome?.winner, deeperSide.opponent, "Game \(gameIndex): \(game.moves)")
            if game.outcome?.winner == deeperSide { deeperWins += 1 }
        }
        XCTAssertGreaterThanOrEqual(deeperWins, 5)
    }
}
