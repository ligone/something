/// A Connect Four position: which cells hold discs, and whose turn it is.
///
/// The board is stored as two bitboards in John Tromp's layout (see
/// `C4Bits`): `current` has the discs of the player to move and `mask` has
/// every disc. Playing a move flips `current` to the other player and adds
/// one bit to `mask`, so a position costs 24 bytes and copying it is the
/// cheapest possible undo.
///
/// `C4Board` enforces only the physical rules (columns hold six discs). It
/// does not stop play after someone connects four; `C4Game` does that.
public struct C4Board: Hashable, Sendable {
    /// Columns on the board.
    public static let columnCount = 7
    /// Rows on the board.
    public static let rowCount = 6
    /// Cells on the board.
    public static let cellCount = 42

    /// Discs of the player to move, one bit per cell.
    public private(set) var current: UInt64
    /// Every disc on the board, one bit per cell.
    public private(set) var mask: UInt64
    /// Number of discs on the board.
    public private(set) var moveCount: Int

    /// The empty board.
    public init() {
        current = 0
        mask = 0
        moveCount = 0
    }

    /// The position after playing `moves`, given as 0-based columns.
    ///
    /// Throws if a column is out of range or full, or if a move comes after
    /// the game was already won.
    public init(moves: [Int]) throws {
        self.init()
        for column in moves {
            guard !isGameOver else { throw C4MoveError.gameOver }
            guard (0..<Self.columnCount).contains(column) else {
                throw C4MoveError.columnOutOfRange(column)
            }
            guard canPlay(column) else { throw C4MoveError.columnFull(column) }
            play(column)
        }
    }

    /// The position after a move sequence in Pascal Pons's notation: one digit
    /// per move, naming columns from 1 to 7. "4453" plays the center column
    /// twice, then columns 5 and 3.
    ///
    /// Returns nil if the string has anything but digits 1–7, or if the
    /// moves are illegal.
    public init?(notation: String) {
        var moves: [Int] = []
        for character in notation {
            guard let digit = character.wholeNumberValue, (1...7).contains(digit) else {
                return nil
            }
            moves.append(digit - 1)
        }
        guard let board = try? C4Board(moves: moves) else { return nil }
        self = board
    }

    // MARK: - Turn and identity

    /// The player whose turn it is.
    public var playerToMove: C4Player {
        moveCount & 1 == 0 ? .first : .second
    }

    /// A number that identifies the position uniquely, used to index the
    /// transposition table.
    ///
    /// Adding `mask` to `current` sets, in each column, the bit just above
    /// the top disc. That marker records the column's height, and the bits
    /// below it record the colors, so no two positions share a key. Keys
    /// fit in 49 bits.
    public var key: UInt64 {
        current &+ mask
    }

    // MARK: - Moves

    /// Whether a disc can be dropped into `column`.
    public func canPlay(_ column: Int) -> Bool {
        column >= 0 && column < Self.columnCount && mask & C4Bits.topCell(column) == 0
    }

    /// Number of discs in `column`.
    public func height(ofColumn column: Int) -> Int {
        precondition((0..<Self.columnCount).contains(column), "Column \(column) is out of range")
        return (mask & C4Bits.column(column)).nonzeroBitCount
    }

    /// The columns that are not full, from left to right.
    public var legalColumns: [Int] {
        (0..<Self.columnCount).filter(canPlay)
    }

    /// Drops a disc for the player to move. The column must not be full.
    public mutating func play(_ column: Int) {
        precondition(canPlay(column), "Column \(column) cannot take another disc")
        current ^= mask
        mask |= mask &+ C4Bits.bottomCell(column)
        moveCount += 1
    }

    /// The position after dropping a disc into `column`, or nil if the column
    /// is out of range or full.
    public func playing(_ column: Int) -> C4Board? {
        guard canPlay(column) else { return nil }
        var next = self
        next.play(column)
        return next
    }

    /// Whether the top disc of `column` belongs to the player who moved last,
    /// so that taking it back gives a position that could have come before.
    public func canUndo(_ column: Int) -> Bool {
        guard column >= 0, column < Self.columnCount else { return false }
        let discs = mask & C4Bits.column(column)
        guard discs != 0 else { return false }
        let top = (discs &+ C4Bits.bottomCell(column)) &>> 1
        return current & top == 0
    }

    /// Takes back the top disc of `column`. That disc must belong to the
    /// player who moved last; see `canUndo(_:)`.
    public mutating func undo(_ column: Int) {
        precondition(canUndo(column), "The top disc of column \(column) cannot be taken back")
        let top = ((mask & C4Bits.column(column)) &+ C4Bits.bottomCell(column)) &>> 1
        mask ^= top
        current ^= mask
        moveCount -= 1
    }

    /// The position before the top disc of `column` was played, or nil if
    /// that disc cannot be taken back.
    public func undoing(_ column: Int) -> C4Board? {
        guard canUndo(column) else { return nil }
        var previous = self
        previous.undo(column)
        return previous
    }

    // MARK: - Wins and threats

    /// Whether dropping a disc into `column` connects four for the player to
    /// move.
    public func isWinningMove(_ column: Int) -> Bool {
        guard canPlay(column) else { return false }
        let wins = C4Bits.winningCells(current, mask) & C4Bits.landingCells(mask)
        return wins & C4Bits.column(column) != 0
    }

    /// Whether the player to move can connect four with their next disc.
    public var canWinNext: Bool {
        C4Bits.winningCells(current, mask) & C4Bits.landingCells(mask) != 0
    }

    /// Whether `player` has four in a row anywhere, checked in all four
    /// directions.
    public func hasFour(for player: C4Player) -> Bool {
        C4Bits.hasFour(discs(of: player))
    }

    /// The player with four in a row, if any.
    ///
    /// Only the player who moved last can have one, unless play continued
    /// after a win.
    public var winner: C4Player? {
        if C4Bits.hasFour(current ^ mask) { return playerToMove.opponent }
        if C4Bits.hasFour(current) { return playerToMove }
        return nil
    }

    /// Whether all 42 cells are taken.
    public var isFull: Bool {
        moveCount >= Self.cellCount
    }

    /// Whether the game has been won or the board is full.
    public var isGameOver: Bool {
        isFull || winner != nil
    }

    /// Every run of four or more discs of `player`, for highlighting a win.
    public func winningLines(for player: C4Player) -> [C4Line] {
        let discs = self.discs(of: player)
        guard C4Bits.hasFour(discs) else { return [] }

        func contains(_ column: Int, _ row: Int) -> Bool {
            guard (0..<Self.columnCount).contains(column), (0..<Self.rowCount).contains(row) else {
                return false
            }
            return discs & C4Bits.cell(column: column, row: row) != 0
        }

        var lines: [C4Line] = []
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        for (dx, dy) in directions {
            for column in 0..<Self.columnCount {
                for row in 0..<Self.rowCount {
                    // Start only from the first disc of a run.
                    guard contains(column, row), !contains(column - dx, row - dy) else { continue }
                    var cells: [C4Cell] = []
                    var x = column
                    var y = row
                    while contains(x, y) {
                        cells.append(C4Cell(column: x, row: y))
                        x += dx
                        y += dy
                    }
                    if cells.count >= 4 {
                        lines.append(C4Line(cells: cells))
                    }
                }
            }
        }
        return lines
    }

    /// Empty cells where a disc of `player` would complete four in a row,
    /// whether or not a disc can land there yet. These are the threats that
    /// Connect Four strategy revolves around.
    public func threats(for player: C4Player) -> [C4Cell] {
        Self.cells(in: C4Bits.winningCells(discs(of: player), mask))
    }

    // MARK: - Cells

    /// The player whose disc fills `cell`, or nil if it is empty or off the
    /// board.
    public func player(at cell: C4Cell) -> C4Player? {
        guard (0..<Self.columnCount).contains(cell.column), (0..<Self.rowCount).contains(cell.row) else {
            return nil
        }
        let bit = C4Bits.cell(column: cell.column, row: cell.row)
        guard mask & bit != 0 else { return nil }
        return current & bit != 0 ? playerToMove : playerToMove.opponent
    }

    /// The discs of `player` as a bitboard.
    public func discs(of player: C4Player) -> UInt64 {
        player == playerToMove ? current : current ^ mask
    }

    /// The same position reflected left to right.
    public var mirrored: C4Board {
        var result = C4Board()
        result.current = C4Bits.mirrored(current)
        result.mask = C4Bits.mirrored(mask)
        result.moveCount = moveCount
        return result
    }

    /// The cells of a bitboard, column by column from the bottom.
    static func cells(in bits: UInt64) -> [C4Cell] {
        var cells: [C4Cell] = []
        var remaining = bits & C4Bits.playable
        while remaining != 0 {
            let index = remaining.trailingZeroBitCount
            remaining &= remaining &- 1
            cells.append(C4Cell(column: index / 7, row: index % 7))
        }
        return cells
    }
}

extension C4Board: CustomStringConvertible {
    /// The board as text, top row first: `X` for the first player, `O` for the
    /// second and `.` for an empty cell.
    public var description: String {
        var rows: [String] = []
        for row in (0..<Self.rowCount).reversed() {
            var line = ""
            for column in 0..<Self.columnCount {
                switch player(at: C4Cell(column: column, row: row)) {
                case .first?: line += "X"
                case .second?: line += "O"
                case nil: line += "."
                }
            }
            rows.append(line)
        }
        return rows.joined(separator: "\n")
    }
}
