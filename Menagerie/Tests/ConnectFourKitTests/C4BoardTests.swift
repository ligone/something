import XCTest
@testable import ConnectFourKit

final class C4BoardTests: XCTestCase {
    // MARK: - Layout

    func testBitConstantsMatchTheirDefinitions() {
        var bottom: UInt64 = 0
        var playable: UInt64 = 0
        var odd: UInt64 = 0
        var even: UInt64 = 0
        for column in 0..<7 {
            bottom |= C4Bits.cell(column: column, row: 0)
            for row in 0..<6 {
                let cell = C4Bits.cell(column: column, row: row)
                playable |= cell
                if row % 2 == 0 { odd |= cell } else { even |= cell }
            }
        }
        XCTAssertEqual(C4Bits.bottomRow, bottom)
        XCTAssertEqual(C4Bits.playable, playable)
        XCTAssertEqual(C4Bits.oddRows, odd)
        XCTAssertEqual(C4Bits.evenRows, even)
    }

    func testEmptyBoard() {
        let board = C4Board()
        XCTAssertEqual(board.moveCount, 0)
        XCTAssertEqual(board.playerToMove, .first)
        XCTAssertEqual(board.legalColumns, Array(0..<7))
        XCTAssertNil(board.winner)
        XCTAssertFalse(board.isGameOver)
        XCTAssertFalse(board.canWinNext)
        XCTAssertEqual(board.description, String(repeating: ".......\n", count: 5) + ".......")
    }

    func testDiscsStackAndPlayersAlternate() throws {
        let board = try C4Board(moves: [3, 3, 2])
        XCTAssertEqual(board.moveCount, 3)
        XCTAssertEqual(board.playerToMove, .second)
        XCTAssertEqual(board.height(ofColumn: 3), 2)
        XCTAssertEqual(board.height(ofColumn: 2), 1)
        XCTAssertEqual(board.player(at: C4Cell(column: 3, row: 0)), .first)
        XCTAssertEqual(board.player(at: C4Cell(column: 3, row: 1)), .second)
        XCTAssertEqual(board.player(at: C4Cell(column: 2, row: 0)), .first)
        XCTAssertNil(board.player(at: C4Cell(column: 3, row: 2)))
        XCTAssertNil(board.player(at: C4Cell(column: 9, row: 0)))
        XCTAssertEqual(board.description.split(separator: "\n").last, "..XX...")
    }

    // MARK: - Wins in all four directions

    func testHorizontalWinIsDetected() throws {
        // X: bottom row, columns 1–4. O stacks on top of them.
        let board = try C4Board(moves: [1, 1, 2, 2, 3, 3, 4])
        XCTAssertEqual(board.winner, .first)
        XCTAssertTrue(board.hasFour(for: .first))
        XCTAssertFalse(board.hasFour(for: .second))
        XCTAssertEqual(cells(of: board.winningLines(for: .first)), [[1, 0], [2, 0], [3, 0], [4, 0]])
    }

    func testVerticalWinIsDetected() throws {
        let board = try C4Board(moves: [0, 1, 0, 1, 0, 1, 0])
        XCTAssertEqual(board.winner, .first)
        XCTAssertEqual(cells(of: board.winningLines(for: .first)), [[0, 0], [0, 1], [0, 2], [0, 3]])
    }

    func testRisingDiagonalWinIsDetected() throws {
        // X climbs from (0,0) to (3,3).
        let board = try C4Board(moves: [0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3])
        XCTAssertEqual(board.winner, .first)
        XCTAssertEqual(cells(of: board.winningLines(for: .first)), [[0, 0], [1, 1], [2, 2], [3, 3]])
    }

    func testFallingDiagonalWinIsDetected() throws {
        // The mirror image of the rising case: X falls from (3,3) to (6,0).
        let board = try C4Board(moves: [0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3].map { 6 - $0 })
        XCTAssertEqual(board.winner, .first)
        XCTAssertEqual(cells(of: board.winningLines(for: .first)), [[3, 3], [4, 2], [5, 1], [6, 0]])
    }

    func testSecondPlayerWinIsDetected() throws {
        let board = try C4Board(moves: [0, 6, 1, 6, 0, 6, 1, 6])
        XCTAssertEqual(board.winner, .second)
        XCTAssertTrue(board.isGameOver)
    }

    func testLinesDoNotWrapFromOneColumnIntoTheNext() {
        // The top three cells of column 0 and the bottom cell of column 1 sit
        // at bits 3, 4, 5 and 7. Without the empty sentinel bit 6 between
        // them, a shift by one would see a vertical four.
        let discs = C4Bits.cell(column: 0, row: 3) | C4Bits.cell(column: 0, row: 4)
            | C4Bits.cell(column: 0, row: 5) | C4Bits.cell(column: 1, row: 0)
        XCTAssertFalse(C4Bits.hasFour(discs))
    }

    func testFourDetectionMatchesAScanOfEveryLine() {
        var generator = C4SplitMix64(seed: 1)
        for _ in 0..<3000 {
            var bits: UInt64 = 0
            var cells: Set<C4Cell> = []
            let density = Double.random(in: 0.2...0.6, using: &generator)
            for column in 0..<7 {
                for row in 0..<6 where Double.random(in: 0..<1, using: &generator) < density {
                    bits |= C4Bits.cell(column: column, row: row)
                    cells.insert(C4Cell(column: column, row: row))
                }
            }
            XCTAssertEqual(C4Bits.hasFour(bits), Reference.hasFour(cells))
        }
    }

    func testThreatsMatchAScanOfEveryLine() {
        for board in Reference.randomPositions(count: 400, discs: 4...30, seed: 2) {
            for player in C4Player.allCases {
                XCTAssertEqual(Set(board.threats(for: player)), Reference.threats(of: player, on: board))
            }
        }
    }

    func testWinningMovesAreExactlyTheMovesThatConnectFour() {
        for board in Reference.randomPositions(count: 400, discs: 4...34, seed: 3) {
            let mover = board.playerToMove
            for column in board.legalColumns {
                let after = board.playing(column)!
                XCTAssertEqual(board.isWinningMove(column), after.hasFour(for: mover))
            }
            XCTAssertEqual(board.canWinNext, board.legalColumns.contains(where: board.isWinningMove))
        }
    }

    // MARK: - Play and undo

    func testPlayAndUndoKeepTheBoardConsistent() {
        var generator = C4SplitMix64(seed: 4)
        for _ in 0..<200 {
            var board = C4Board()
            var history: [C4Board] = [board]
            var moves: [Int] = []
            while !board.isGameOver {
                let column = board.legalColumns.randomElement(using: &generator)!
                XCTAssertEqual(board.playing(column)?.undoing(column), board)
                board.play(column)
                moves.append(column)
                history.append(board)
                XCTAssertEqual(board.moveCount, moves.count)
                XCTAssertEqual(board.mask.nonzeroBitCount, moves.count)
                XCTAssertEqual(board.current & ~board.mask, 0, "Discs outside the mask")
            }
            // Unwind the whole game with the bitboard undo.
            while let column = moves.popLast() {
                XCTAssertTrue(board.canUndo(column))
                board.undo(column)
                history.removeLast()
                XCTAssertEqual(board, history.last)
            }
            XCTAssertEqual(board, C4Board())
        }
    }

    func testUndoRefusesTheOpponentsDisc() throws {
        let board = try C4Board(moves: [3, 4])
        XCTAssertTrue(board.canUndo(4), "The last mover's disc can be taken back")
        XCTAssertFalse(board.canUndo(3), "That disc belongs to the player to move")
        XCTAssertFalse(board.canUndo(0), "Empty column")
        XCTAssertNil(board.undoing(3))
    }

    func testKeysAreUnique() {
        var generator = C4SplitMix64(seed: 5)
        var seen: [UInt64: C4Board] = [:]
        for _ in 0..<500 {
            let game = Reference.randomGame(discs: 42, using: &generator)
            var board = C4Board()
            for column in game.moves {
                board.play(column)
                if let other = seen[board.key] {
                    XCTAssertEqual(other, board, "Two positions share a key")
                }
                seen[board.key] = board
                XCTAssertLessThan(board.key, 1 << 49)
            }
        }
    }

    // MARK: - Construction

    func testIllegalMovesAreRejected() throws {
        var board = C4Board()
        for _ in 0..<6 { board.play(2) }
        XCTAssertFalse(board.canPlay(2))
        XCTAssertNil(board.playing(2))
        XCTAssertFalse(board.canPlay(-1))
        XCTAssertFalse(board.canPlay(7))
        XCTAssertNil(board.playing(7))
        XCTAssertFalse(board.legalColumns.contains(2))

        XCTAssertThrowsError(try C4Board(moves: [2, 2, 2, 2, 2, 2, 2])) { error in
            XCTAssertEqual(error as? C4MoveError, .columnFull(2))
        }
        XCTAssertThrowsError(try C4Board(moves: [8])) { error in
            XCTAssertEqual(error as? C4MoveError, .columnOutOfRange(8))
        }
        // The first player wins with the seventh move, so an eighth is refused.
        XCTAssertThrowsError(try C4Board(moves: [0, 1, 0, 1, 0, 1, 0, 1])) { error in
            XCTAssertEqual(error as? C4MoveError, .gameOver)
        }
    }

    func testNotation() throws {
        XCTAssertEqual(C4Board(notation: "4453"), try C4Board(moves: [3, 3, 4, 2]))
        XCTAssertEqual(C4Board(notation: ""), C4Board())
        XCTAssertNil(C4Board(notation: "48"), "8 is not a column")
        XCTAssertNil(C4Board(notation: "4a"), "Not a digit")
        XCTAssertNil(C4Board(notation: "1111111"), "Column 1 overflows")
    }

    func testMirroring() {
        for board in Reference.randomPositions(count: 100, discs: 1...30, seed: 6) {
            let mirror = board.mirrored
            XCTAssertEqual(mirror.mirrored, board)
            XCTAssertEqual(mirror.moveCount, board.moveCount)
            for column in 0..<7 {
                for row in 0..<6 {
                    XCTAssertEqual(
                        mirror.player(at: C4Cell(column: 6 - column, row: row)),
                        board.player(at: C4Cell(column: column, row: row))
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    /// The cells of each line as [column, row] pairs, for compact asserts.
    private func cells(of lines: [C4Line]) -> [[Int]] {
        XCTAssertEqual(lines.count, 1, "Expected exactly one winning line")
        return lines.first?.cells.map { [$0.column, $0.row] } ?? []
    }
}
