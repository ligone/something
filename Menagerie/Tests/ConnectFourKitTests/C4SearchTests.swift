import Foundation
import XCTest
@testable import ConnectFourKit

final class C4SearchTests: XCTestCase {
    /// A small table keeps the tests light. It still gets 2¹⁷ buckets.
    private func makeEngine() -> C4Engine {
        C4Engine(tableSize: 1 << 18)
    }

    // MARK: - Tactics

    func testTakesAWinOnTheSpot() {
        // X has the bottom row of columns 0–2; column 3 completes it.
        let board = C4Board.position("112233")
        let analysis = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 8))
        XCTAssertEqual(analysis.bestColumn, 3)
        XCTAssertEqual(analysis.scores[3], .win(inMoves: 1))
        XCTAssertTrue(analysis.exactColumns[3])
    }

    func testBlocksAnImmediateThreat() {
        // O to move, and X threatens the bottom row at column 3.
        let board = C4Board.position("11223")
        let analysis = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 8))
        XCTAssertEqual(analysis.bestColumn, 3)
        for column in analysis.scoredColumns where column != 3 {
            XCTAssertEqual(analysis.scores[column], .loss(inMoves: 1), "Column \(column) ignores the threat")
        }
    }

    func testNeverFillsTheCellBeneathAnOpponentThreat() {
        // X has (1,1) (2,1) (3,1) and threatens (0,1) and (4,1). Whoever
        // fills (0,0) or (4,0) lets X complete the row.
        let board = C4Board.position("2324374")
        XCTAssertEqual(board.playerToMove, .second)
        let analysis = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 8))
        XCTAssertEqual(analysis.scores[0], .loss(inMoves: 1))
        XCTAssertEqual(analysis.scores[4], .loss(inMoves: 1))
        XCTAssertFalse([0, 4].contains(analysis.bestColumn))
    }

    func testFindsADoubleThreatWinInTwo() {
        // X has (3,0) and (4,0). Column 2 or 5 makes three in a row with both
        // ends open, and O can block only one of them.
        let board = C4Board.position("4455")
        let analysis = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 6))
        XCTAssertEqual(analysis.scores[2], .win(inMoves: 2))
        XCTAssertEqual(analysis.scores[5], .win(inMoves: 2))
        XCTAssertTrue([2, 5].contains(analysis.bestColumn))
    }

    func testFindsAForcedWinInThree() {
        assertForcedWin(in: "4244633142", column: 6, moves: 3)
    }

    func testFindsAForcedWinInFour() {
        assertForcedWin(in: "6133355442", column: 3, moves: 4)
    }

    /// Checks that `column` is the only way to force a win within `moves`,
    /// using an independent mate search, and that the engine finds it.
    private func assertForcedWin(in notation: String, column: Int, moves: Int, file: StaticString = #filePath, line: UInt = #line) {
        let board = C4Board.position(notation)
        let finder = MateFinder()
        XCTAssertTrue(finder.winsAfter(column, in: board, within: moves), "Not a forced win", file: file, line: line)
        XCTAssertFalse(finder.winsAfter(column, in: board, within: moves - 1), "Wins faster", file: file, line: line)
        for other in board.legalColumns where other != column {
            XCTAssertFalse(finder.winsAfter(other, in: board, within: moves), "Column \(other) also wins", file: file, line: line)
        }

        let analysis = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 2 * moves + 2))
        XCTAssertEqual(analysis.bestColumn, column, file: file, line: line)
        XCTAssertEqual(analysis.scores[column], .win(inMoves: moves), file: file, line: line)
        XCTAssertTrue(analysis.exactColumns[column], file: file, line: line)

        // The expected line of play ends in four in a row.
        var replay = board
        for move in analysis.principalVariation {
            XCTAssertTrue(replay.canPlay(move), file: file, line: line)
            replay.play(move)
        }
        XCTAssertTrue(replay.hasFour(for: board.playerToMove), "Line \(analysis.principalVariation)", file: file, line: line)
    }

    // MARK: - Exact results

    func testSolvedScoresMatchExhaustiveMinimax() {
        let engine = makeEngine()
        let solver = ReferenceSolver()
        for board in Reference.randomPositions(count: 150, discs: 28...36, seed: 31) {
            let analysis = engine.analyze(board)
            XCTAssertTrue(analysis.isSolved)
            for column in 0..<7 {
                if board.canPlay(column) {
                    XCTAssertEqual(
                        analysis.scores[column],
                        solver.expectedScore(of: column, in: board),
                        "Column \(column) of\n\(board)"
                    )
                } else {
                    XCTAssertNil(analysis.scores[column])
                }
            }
            // The mirror image scores the mirrored columns the same.
            let mirrored = engine.analyze(board.mirrored)
            XCTAssertEqual(mirrored.scores, Array(analysis.scores.reversed()))
        }
    }

    func testForcedResultsAreRealAndExactWhenMarked() {
        let engine = makeEngine()
        var checked = 0
        let boards = Reference.randomPositions(count: 250, discs: 8...30, seed: 41)
        for (index, board) in boards.enumerated() {
            // Shallow searches, where single-reply extensions reach furthest
            // past the horizon.
            let analysis = engine.analyze(board, limits: C4SearchLimits(maxDepth: 2 + index % 8))
            for column in analysis.scoredColumns {
                let finder = MateFinder()
                let exact = analysis.exactColumns[column]
                switch analysis.scores[column]! {
                case .win(let moves) where moves <= 5:
                    if moves == 1 {
                        XCTAssertTrue(board.isWinningMove(column))
                    } else {
                        XCTAssertTrue(finder.winsAfter(column, in: board, within: moves), "\(board)")
                        if exact {
                            XCTAssertFalse(finder.winsAfter(column, in: board, within: moves - 1), "\(board)")
                        }
                    }
                    checked += 1
                case .loss(let moves) where moves <= 5:
                    let child = board.playing(column)!
                    XCTAssertTrue(finder.canForceWin(child, within: moves), "\(board)")
                    if exact {
                        XCTAssertFalse(finder.canForceWin(child, within: moves - 1), "\(board)")
                    }
                    checked += 1
                default:
                    break
                }
            }
        }
        XCTAssertGreaterThan(checked, 300)
    }

    func testPonsBenchmarkPosition() {
        // The first position of Pascal Pons's end-game benchmark set,
        // Test_L3_R1, given in his notation with its published score of −1:
        // the player to move loses to the opponent's last possible disc.
        let board = C4Board.position("2252576253462244111563365343671351441")
        let analysis = makeEngine().analyze(board)
        XCTAssertTrue(analysis.isSolved)
        XCTAssertEqual(ponsScore(of: analysis.bestScore!, discs: board.moveCount), -1)

        let solver = ReferenceSolver()
        let best = board.legalColumns.map { solver.expectedScore(of: $0, in: board) }.max()
        XCTAssertEqual(analysis.bestScore, best)
    }

    func testDrawIsReportedOnlyWhenProven() {
        // An endgame that best play fills without four in a row.
        let board = C4Board.position("23163416124767223154467471272416755633")
        let solved = makeEngine().analyze(board)
        XCTAssertTrue(solved.isSolved)
        XCTAssertEqual(solved.bestScore, .draw)
        XCTAssertEqual(ponsScore(of: solved.bestScore!, discs: board.moveCount), 0)

        // A shallow search cannot know, so it only estimates.
        let shallow = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 1))
        XCTAssertFalse(shallow.scores.contains(.draw))
    }

    func testAnalysisRanksTheWinningColumnHighest() {
        let board = C4Board.position("6133355442")
        let analysis = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 10))
        let winning = analysis.scores[3]!
        for column in analysis.scoredColumns where column != 3 {
            XCTAssertLessThan(analysis.scores[column]!, winning)
        }
        XCTAssertEqual(analysis.bestScore, winning)
    }

    func testFinishedGameHasNoScores() {
        let board = C4Board.position("1212121")
        XCTAssertEqual(board.winner, .first)
        let analysis = makeEngine().analyze(board)
        XCTAssertTrue(analysis.scores.allSatisfy { $0 == nil })
        XCTAssertNil(analysis.bestColumn)
    }

    // MARK: - Play

    func testNeverLosesToARandomPlayer() throws {
        var generator = C4SplitMix64(seed: 51)
        let engine = makeEngine()
        let limits = C4SearchLimits(maxDepth: 6)
        for gameIndex in 0..<40 {
            var game = C4Game()
            let engineSide: C4Player = gameIndex % 2 == 0 ? .first : .second
            while !game.isOver {
                let column: Int
                if game.playerToMove == engineSide {
                    let analysis = engine.analyze(game.board, limits: limits)
                    let choice = C4Difficulty.ruthless.chooseColumn(from: analysis, using: &generator)
                    column = try XCTUnwrap(choice)
                } else {
                    column = game.board.legalColumns.randomElement(using: &generator)!
                }
                try game.play(column)
            }
            XCTAssertNotEqual(game.outcome?.winner, engineSide.opponent, "Lost game \(gameIndex): \(game.moves)")
        }
    }

    // MARK: - Limits and progress

    func testStopFlagEndsTheSearchPromptly() {
        let engine = makeEngine()
        let flag = C4StopFlag()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            flag.raise()
        }
        let started = Date()
        let analysis = engine.analyze(C4Board(), limits: C4SearchLimits(), shouldStop: { flag.isRaised })
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        XCTAssertTrue(flag.isRaised)
        XCTAssertGreaterThanOrEqual(analysis.depth, 1)
        XCTAssertTrue([2, 3, 4].contains(analysis.bestColumn), "Opens in the middle")
        XCTAssertFalse(analysis.isSolved)
    }

    func testTimeBudgetIsRespected() {
        let started = Date()
        let analysis = makeEngine().analyze(C4Board(), limits: C4SearchLimits(maxDepth: 42, timeBudget: 0.25))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
        XCTAssertGreaterThanOrEqual(analysis.depth, 4)
        XCTAssertFalse(analysis.isSolved)
    }

    func testUpdatesReportEachFinishedIteration() {
        var finished: [Int] = []
        var lastNodes = 0
        let analysis = makeEngine().analyze(
            C4Board.position("4453"),
            limits: C4SearchLimits(maxDepth: 8),
            onUpdate: { update in
                XCTAssertGreaterThanOrEqual(update.nodes, lastNodes)
                lastNodes = update.nodes
                if update.searchingDepth == update.analysis.depth {
                    finished.append(update.analysis.depth)
                }
            }
        )
        XCTAssertEqual(finished, Array(1...8))
        XCTAssertEqual(analysis.depth, 8)
        XCTAssertGreaterThanOrEqual(analysis.nodes, lastNodes)
    }

    func testPrincipalVariationStartsWithTheBestMove() {
        let board = C4Board.position("4453")
        let analysis = makeEngine().analyze(board, limits: C4SearchLimits(maxDepth: 10))
        XCTAssertEqual(analysis.principalVariation.first, analysis.bestColumn)
        var replay = board
        for column in analysis.principalVariation {
            XCTAssertTrue(replay.canPlay(column))
            replay.play(column)
        }
    }

    // MARK: - Internals

    func testTableSizeGuaranteesUniqueKeys() {
        // Buckets × 2³² must exceed 2⁴⁹ for the stored 32 key bits and the
        // bucket index to identify a position.
        let table = C4TranspositionTable(minimumSize: 1000)
        XCTAssertGreaterThan(table.bucketCount, 1 << 17)
        XCTAssertTrue(C4TranspositionTable.isPrime(table.bucketCount))
        XCTAssertFalse(C4TranspositionTable.isPrime(1 << 17))
        XCTAssertEqual(C4TranspositionTable.prime(atLeast: 100), 101)
    }

    func testCellWeightsCountTheLinesThroughEachCell() {
        for row in 0..<6 {
            for column in 0..<7 {
                let lines = Reference.lines.filter { $0.contains(C4Cell(column: column, row: row)) }
                XCTAssertEqual(C4Searcher.cellWeights[row][column], lines.count, "Cell (\(column), \(row))")
            }
        }
    }
}
