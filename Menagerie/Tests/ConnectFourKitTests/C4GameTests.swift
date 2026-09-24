import XCTest
import ConnectFourKit

final class C4GameTests: XCTestCase {
    func testAWinEndsTheGameAndNamesTheFourCells() throws {
        var game = try C4Game(moves: [0, 6, 1, 6, 2, 6])
        XCTAssertNil(game.outcome)
        let outcome = try game.play(3)
        guard case .win(let player, let lines)? = outcome else {
            return XCTFail("Expected a win, got \(String(describing: outcome))")
        }
        XCTAssertEqual(player, .first)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].cells, (0...3).map { C4Cell(column: $0, row: 0) })
        XCTAssertEqual(lines[0].start, C4Cell(column: 0, row: 0))
        XCTAssertEqual(lines[0].end, C4Cell(column: 3, row: 0))
        XCTAssertEqual(game.outcome?.winner, .first)
        XCTAssertEqual(game.outcome?.winningCells.count, 4)
        XCTAssertTrue(game.isOver)
    }

    func testFiveInARowIsOneLine() throws {
        // X fills row 0 at columns 0, 1, 3, 4, then drops into the gap.
        let game = try C4Game(moves: [0, 0, 1, 1, 3, 3, 4, 4, 2])
        guard case .win(.first, let lines)? = game.outcome else {
            return XCTFail("Expected a win for the first player")
        }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].cells.count, 5)
    }

    func testOneMoveCanCompleteTwoLines() throws {
        // X builds (0,0) (1,0) (2,0) along the bottom and (4,1) (5,2) (6,3) up
        // a diagonal, while O fills the cells underneath. Column 3 stays
        // empty, so X's last disc lands on (3,0) and completes both lines.
        var game = try C4Game(moves: [0, 4, 4, 5, 1, 5, 5, 6, 2, 6, 4, 6, 6, 4])
        XCTAssertNil(game.outcome)
        let outcome = try game.play(3)
        guard case .win(.first, let lines)? = outcome else {
            return XCTFail("Expected a win for the first player, got \(String(describing: outcome))")
        }
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            Set(lines.map(\.start)),
            [C4Cell(column: 0, row: 0), C4Cell(column: 3, row: 0)]
        )
        XCTAssertEqual(game.outcome?.winningCells.count, 7)
    }

    func testAFullBoardWithNoFourIsADraw() throws {
        // A full game in which nobody connects four.
        let columns = "564562226132237643274151363515673574771441".map { Int(String($0))! - 1 }
        var game = C4Game()
        for (index, column) in columns.enumerated() {
            let outcome = try game.play(column)
            if index < columns.count - 1 {
                XCTAssertNil(outcome, "The game ended early at move \(index + 1)")
            }
        }
        XCTAssertEqual(game.outcome, .draw)
        XCTAssertNil(game.outcome?.winner)
        XCTAssertTrue(game.board.isFull)
        XCTAssertEqual(game.board.legalColumns, [])
        XCTAssertThrowsError(try game.play(0))
    }

    func testIllegalMovesAreRejectedAndChangeNothing() throws {
        var game = try C4Game(moves: [2, 2, 2, 2, 2, 2])
        let before = game

        XCTAssertThrowsError(try game.play(2)) { error in
            XCTAssertEqual(error as? C4MoveError, .columnFull(2))
        }
        XCTAssertThrowsError(try game.play(7)) { error in
            XCTAssertEqual(error as? C4MoveError, .columnOutOfRange(7))
        }
        XCTAssertThrowsError(try game.play(-1)) { error in
            XCTAssertEqual(error as? C4MoveError, .columnOutOfRange(-1))
        }
        XCTAssertEqual(game, before)

        var won = try C4Game(moves: [0, 1, 0, 1, 0, 1, 0])
        XCTAssertThrowsError(try won.play(4)) { error in
            XCTAssertEqual(error as? C4MoveError, .gameOver)
        }
    }

    func testUndoRestoresTheExactPreviousState() throws {
        var generator = C4SplitMix64(seed: 21)
        for _ in 0..<50 {
            var game = C4Game()
            var snapshots: [C4Game] = [game]
            while !game.isOver {
                try game.play(game.board.legalColumns.randomElement(using: &generator)!)
                snapshots.append(game)
            }
            // Undo takes back a winning move too.
            while game.canUndo {
                let column = game.moves.last
                XCTAssertEqual(game.undo(), column)
                snapshots.removeLast()
                XCTAssertEqual(game, snapshots.last)
            }
            XCTAssertNil(game.undo())
            XCTAssertEqual(game, C4Game())
        }
    }

    func testMoveBookkeeping() throws {
        let game = try C4Game(moves: [3, 3, 4])
        XCTAssertEqual(game.moves, [3, 3, 4])
        XCTAssertEqual(game.cell(ofMove: 0), C4Cell(column: 3, row: 0))
        XCTAssertEqual(game.cell(ofMove: 1), C4Cell(column: 3, row: 1))
        XCTAssertEqual(game.cell(ofMove: 2), C4Cell(column: 4, row: 0))
        XCTAssertEqual(game.lastMove, C4Cell(column: 4, row: 0))
        XCTAssertEqual(game.player(ofMove: 1), .second)
        XCTAssertEqual(game.playerToMove, .second)
        XCTAssertNil(C4Game().lastMove)
    }
}
