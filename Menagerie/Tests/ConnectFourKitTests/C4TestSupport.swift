import ConnectFourKit

/// Slow, obviously correct reference implementations that share none of the
/// engine's search code: no pruning, no transposition table, no heuristics.
/// The tests check the fast engine against them.
enum Reference {
    /// All 69 ways to place four in a row on a 7 × 6 board.
    static let lines: [[C4Cell]] = {
        var lines: [[C4Cell]] = []
        for (dx, dy) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
            for column in 0..<7 {
                for row in 0..<6 {
                    let cells = (0..<4).map { C4Cell(column: column + dx * $0, row: row + dy * $0) }
                    if cells.allSatisfy({ (0..<7).contains($0.column) && (0..<6).contains($0.row) }) {
                        lines.append(cells)
                    }
                }
            }
        }
        return lines
    }()

    /// Whether a set of cells contains four in a row, by checking every line.
    static func hasFour(_ cells: Set<C4Cell>) -> Bool {
        lines.contains { line in line.allSatisfy(cells.contains) }
    }

    /// The cells holding `player`'s discs.
    static func cells(of player: C4Player, on board: C4Board) -> Set<C4Cell> {
        var cells: Set<C4Cell> = []
        for column in 0..<7 {
            for row in 0..<6 where board.player(at: C4Cell(column: column, row: row)) == player {
                cells.insert(C4Cell(column: column, row: row))
            }
        }
        return cells
    }

    /// Empty cells where one more disc of `player` would make four in a row.
    static func threats(of player: C4Player, on board: C4Board) -> Set<C4Cell> {
        let own = cells(of: player, on: board)
        var threats: Set<C4Cell> = []
        for line in lines {
            let empty = line.filter { board.player(at: $0) == nil }
            if empty.count == 1, line.filter(own.contains).count == 3 {
                threats.insert(empty[0])
            }
        }
        return threats
    }

    /// Plays random legal moves until `discs` discs are down or the game ends.
    static func randomGame(discs: Int, using generator: inout C4SplitMix64) -> C4Game {
        var game = C4Game()
        while game.moves.count < discs, !game.isOver {
            let column = game.board.legalColumns.randomElement(using: &generator)!
            try! game.play(column)
        }
        return game
    }

    /// Random unfinished positions with `discs` discs each.
    static func randomPositions(count: Int, discs: ClosedRange<Int>, seed: UInt64) -> [C4Board] {
        var generator = C4SplitMix64(seed: seed)
        var boards: [C4Board] = []
        while boards.count < count {
            let target = Int.random(in: discs, using: &generator)
            let game = randomGame(discs: target, using: &generator)
            if !game.isOver, game.moves.count == target {
                boards.append(game.board)
            }
        }
        return boards
    }
}

/// Exhaustive minimax with memoization: the exact result of every column,
/// found by trying every continuation to the end of the game. Only usable
/// when few cells are empty.
final class ReferenceSolver {
    private var memo: [UInt64: Outcome] = [:]

    /// A game-theoretic result for the player to move, with the number of
    /// discs on the board when the game ends.
    enum Outcome: Equatable {
        case win(finalDiscs: Int)
        case loss(finalDiscs: Int)
        case draw

        /// Larger is better for the player to move: quick wins, slow losses.
        var rank: Int {
            switch self {
            case .win(let discs): return 100 - discs
            case .loss(let discs): return -100 + discs
            case .draw: return 0
            }
        }

        var flipped: Outcome {
            switch self {
            case .win(let discs): return .loss(finalDiscs: discs)
            case .loss(let discs): return .win(finalDiscs: discs)
            case .draw: return .draw
            }
        }
    }

    /// The exact outcome of dropping a disc into `column`.
    func outcome(of column: Int, in board: C4Board) -> Outcome {
        if board.isWinningMove(column) {
            return .win(finalDiscs: board.moveCount + 1)
        }
        return outcome(of: board.playing(column)!).flipped
    }

    /// The exact outcome of a position for the player to move.
    func outcome(of board: C4Board) -> Outcome {
        if let known = memo[board.key] { return known }
        var best: Outcome?
        for column in board.legalColumns {
            let result = outcome(of: column, in: board)
            if best == nil || result.rank > best!.rank {
                best = result
            }
        }
        let result = best ?? .draw
        memo[board.key] = result
        return result
    }

    /// The score the engine should report for `column`.
    func expectedScore(of column: Int, in board: C4Board) -> C4Score {
        let discs = board.moveCount
        switch outcome(of: column, in: board) {
        case .win(let finalDiscs): return .win(inMoves: (finalDiscs - discs + 1) / 2)
        case .loss(let finalDiscs): return .loss(inMoves: (finalDiscs - discs) / 2)
        case .draw: return .draw
        }
    }
}

/// A bounded mate search: can the player to move force four in a row with
/// one of their next `moves` discs, whatever the opponent does?
final class MateFinder {
    // Memo: positive n means "can force within n", negative n means
    // "cannot force within |n|".
    private var memo: [UInt64: Int] = [:]

    func canForceWin(_ board: C4Board, within moves: Int) -> Bool {
        guard moves > 0 else { return false }
        if let known = memo[board.key] {
            if known > 0, known <= moves { return true }
            if known < 0, -known >= moves { return false }
        }

        var result = board.legalColumns.contains(where: board.isWinningMove)
        if !result, moves > 1 {
            result = board.legalColumns.contains { column in
                winsAfter(column, in: board, within: moves)
            }
        }

        if result {
            memo[board.key] = min(memo[board.key].map { $0 > 0 ? $0 : moves } ?? moves, moves)
        } else if (memo[board.key] ?? 0) <= 0 {
            memo[board.key] = -max(-(memo[board.key] ?? 0), moves)
        }
        return result
    }

    /// Whether dropping into `column` (not an immediate win) forces a win
    /// within `moves` discs counting this one: every reply must leave a win
    /// within `moves - 1`.
    func winsAfter(_ column: Int, in board: C4Board, within moves: Int) -> Bool {
        guard moves > 1, let child = board.playing(column), !child.isFull else { return false }
        return child.legalColumns.allSatisfy { reply in
            !child.isWinningMove(reply) && canForceWin(child.playing(reply)!, within: moves - 1)
        }
    }
}

/// Pascal Pons's score convention: positive when the player to move can
/// force a win, larger the sooner; 0 for a draw.
func ponsScore(of score: C4Score, discs: Int) -> Int {
    switch score {
    case .win(let moves):
        let finalDiscs = discs + 2 * moves - 1
        return (44 - finalDiscs) / 2
    case .loss(let moves):
        let finalDiscs = discs + 2 * moves
        return -((44 - finalDiscs) / 2)
    case .draw, .estimate:
        return 0
    }
}

extension C4Board {
    /// Builds a board from Pons's notation, failing the test on bad input.
    static func position(_ notation: String) -> C4Board {
        guard let board = C4Board(notation: notation) else {
            preconditionFailure("Invalid move sequence \(notation)")
        }
        return board
    }
}
