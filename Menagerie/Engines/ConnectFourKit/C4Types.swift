// ConnectFourKit: a Connect Four engine built on bitboards and game-tree search.
//
// The module has three layers:
//
//  • `C4Board` and `C4Game` hold the rules, on John Tromp's 49-bit bitboard
//    layout. `C4Board` is a small value type, so undo is simply keeping a copy.
//  • `C4Engine` runs negamax with alpha-beta pruning, iterative deepening and
//    a transposition table, and scores every legal column, not only the best.
//  • `C4Difficulty` turns an analysis into a move, adding some randomness at
//    the easier levels.
//
// Everything here is plain Swift with Foundation and Dispatch, so it builds and
// is tested on Linux as well as macOS.

/// One of the two players.
///
/// The engine does not deal in colors: `first` is whoever dropped the first
/// disc, and `second` is their opponent.
public enum C4Player: Int, CaseIterable, Hashable, Sendable {
    case first
    case second

    /// The other player.
    public var opponent: C4Player {
        self == .first ? .second : .first
    }
}

/// A cell of the 7 × 6 grid. Columns count from 0 at the left, rows from 0 at
/// the bottom.
public struct C4Cell: Hashable, Sendable, CustomStringConvertible {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    public var description: String {
        "(\(column), \(row))"
    }
}

/// A straight run of four or more discs of one player.
public struct C4Line: Hashable, Sendable {
    /// The cells of the run, in order from one end to the other. There are
    /// always at least four.
    public let cells: [C4Cell]

    public init(cells: [C4Cell]) {
        precondition(cells.count >= 4, "A line needs at least four cells")
        self.cells = cells
    }

    /// The first cell of the run.
    public var start: C4Cell { cells[0] }

    /// The last cell of the run.
    public var end: C4Cell { cells[cells.count - 1] }
}

/// How a finished game ended.
public enum C4Outcome: Hashable, Sendable {
    /// `player` connected four. `lines` lists every run of four or more of
    /// their discs; a single move can complete more than one.
    case win(C4Player, lines: [C4Line])
    /// The board filled up with no four in a row.
    case draw

    /// The winning player, or nil for a draw.
    public var winner: C4Player? {
        if case .win(let player, _) = self { return player }
        return nil
    }

    /// Every cell that belongs to a winning line.
    public var winningCells: Set<C4Cell> {
        guard case .win(_, let lines) = self else { return [] }
        return Set(lines.flatMap(\.cells))
    }
}

/// Why a move was refused.
public enum C4MoveError: Error, Hashable, Sendable {
    /// The column index is not in `0..<7`.
    case columnOutOfRange(Int)
    /// All six cells of the column are taken.
    case columnFull(Int)
    /// The game is already won or drawn.
    case gameOver
}
