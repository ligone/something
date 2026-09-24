/// A game in progress: the current board, the moves that led to it, and the
/// result once someone connects four or the board fills.
///
/// Unlike `C4Board`, a game refuses moves after it ends. Undo restores a
/// saved copy of the previous board, so it is exact and costs nothing.
public struct C4Game: Hashable, Sendable {
    /// The current position.
    public private(set) var board = C4Board()
    /// Columns played so far, in order.
    public private(set) var moves: [Int] = []
    /// How the game ended, or nil while it is still going.
    public private(set) var outcome: C4Outcome?
    /// The board before each move, so `history[i]` is the position in which
    /// `moves[i]` was played.
    private var history: [C4Board] = []

    /// A new game on an empty board.
    public init() {}

    /// A game with `moves` already played, as 0-based columns.
    public init(moves: [Int]) throws {
        for column in moves {
            try play(column)
        }
    }

    /// Whether the game has been won or drawn.
    public var isOver: Bool {
        outcome != nil
    }

    /// The player whose turn it is.
    public var playerToMove: C4Player {
        board.playerToMove
    }

    /// Whether there is a move to take back.
    public var canUndo: Bool {
        !moves.isEmpty
    }

    /// The cell where the move at `index` landed.
    public func cell(ofMove index: Int) -> C4Cell {
        let column = moves[index]
        return C4Cell(column: column, row: history[index].height(ofColumn: column))
    }

    /// The cell of the most recent disc, if any.
    public var lastMove: C4Cell? {
        moves.isEmpty ? nil : cell(ofMove: moves.count - 1)
    }

    /// The player who made the move at `index`.
    public func player(ofMove index: Int) -> C4Player {
        index & 1 == 0 ? .first : .second
    }

    /// Drops a disc for the player to move and returns the outcome if the move
    /// ended the game.
    ///
    /// Throws `C4MoveError` if the column is out of range or full, or if the
    /// game is already over. A refused move leaves the game unchanged.
    @discardableResult
    public mutating func play(_ column: Int) throws -> C4Outcome? {
        guard outcome == nil else { throw C4MoveError.gameOver }
        guard (0..<C4Board.columnCount).contains(column) else {
            throw C4MoveError.columnOutOfRange(column)
        }
        guard board.canPlay(column) else { throw C4MoveError.columnFull(column) }

        let mover = board.playerToMove
        history.append(board)
        board.play(column)
        moves.append(column)

        if board.hasFour(for: mover) {
            outcome = .win(mover, lines: board.winningLines(for: mover))
        } else if board.isFull {
            outcome = .draw
        }
        return outcome
    }

    /// Takes back the last move and returns its column, or nil if no move has
    /// been played.
    @discardableResult
    public mutating func undo() -> Int? {
        guard let column = moves.popLast() else { return nil }
        board = history.removeLast()
        outcome = nil
        return column
    }
}
