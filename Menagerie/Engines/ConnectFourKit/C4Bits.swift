/// Bit tricks on John Tromp's board layout.
///
/// A set of cells fits in one `UInt64`, with 7 bits per column: 6 bits for the
/// rows, bottom row first, then a sentinel bit that is always 0.
///
///      6 13 20 27 34 41 48    ← sentinel row, always empty
///      5 12 19 26 33 40 47
///      4 11 18 25 32 39 46
///      3 10 17 24 31 38 45
///      2  9 16 23 30 37 44
///      1  8 15 22 29 36 43
///      0  7 14 21 28 35 42
///
/// Shifting a bitboard moves every disc at once: by 1 to go up a row, by 7 to
/// go one column to the right, and by 6 or 8 to follow the two diagonals. The
/// empty sentinel row stops shifted patterns from wrapping into the next
/// column, so a few shifts and ANDs test all 69 possible lines in parallel.
///
/// Debug builds compile the engine file by file, without whole-module
/// optimization, so these helpers are `@inlinable`. That lets the searcher
/// inline them across files, which keeps debug builds within reach of
/// release speed.
@usableFromInline
enum C4Bits {
    /// One bit at the bottom of each column.
    @usableFromInline static let bottomRow: UInt64 = 0x0000_0408_1020_4081

    /// All 42 cells of the board, without the sentinel row.
    @usableFromInline static let playable: UInt64 = 0x0000_FDFB_F7EF_DFBF

    /// Rows 1, 3 and 5 counted from 1 at the bottom (indices 0, 2 and 4).
    /// Threats on these rows favor the first player.
    @usableFromInline static let oddRows: UInt64 = 0x0000_54A9_52A5_4A95

    /// Rows 2, 4 and 6 counted from 1 at the bottom (indices 1, 3 and 5).
    /// Threats on these rows favor the second player.
    @usableFromInline static let evenRows: UInt64 = 0x0000_A952_A54A_952A

    /// The six cells of a column.
    @inlinable
    static func column(_ column: Int) -> UInt64 {
        UInt64(0x3F) &<< (column &* 7)
    }

    /// The bottom cell of a column.
    @inlinable
    static func bottomCell(_ column: Int) -> UInt64 {
        UInt64(1) &<< (column &* 7)
    }

    /// The top cell of a column.
    @inlinable
    static func topCell(_ column: Int) -> UInt64 {
        UInt64(1) &<< (column &* 7 &+ 5)
    }

    /// A single cell.
    @inlinable
    static func cell(column: Int, row: Int) -> UInt64 {
        UInt64(1) &<< (column &* 7 &+ row)
    }

    /// The cell where the next disc would land in every column that is not
    /// full. Adding the bottom row carries each column's bit up past its discs.
    @inlinable
    static func landingCells(_ mask: UInt64) -> UInt64 {
        (mask &+ bottomRow) & playable
    }

    /// Every empty cell that would complete four in a row for `discs`, whether
    /// or not a disc can be dropped there yet.
    @inlinable
    static func winningCells(_ discs: UInt64, _ mask: UInt64) -> UInt64 {
        // Vertical: an empty cell above three stacked discs.
        var cells = (discs &<< 1) & (discs &<< 2) & (discs &<< 3)
        // Horizontal, then the two diagonals.
        cells |= alignedGaps(discs, 7)
        cells |= alignedGaps(discs, 6)
        cells |= alignedGaps(discs, 8)
        return cells & (playable ^ mask)
    }

    /// Cells that complete three discs along the direction of `shift`, with
    /// the gap at either end of the four or between the discs.
    @inlinable
    static func alignedGaps(_ discs: UInt64, _ shift: Int) -> UInt64 {
        var cells: UInt64 = 0
        var pair = (discs &<< shift) & (discs &<< (2 &* shift))
        cells |= pair & (discs &<< (3 &* shift))
        cells |= pair & (discs &>> shift)
        pair = (discs &>> shift) & (discs &>> (2 &* shift))
        cells |= pair & (discs &<< shift)
        cells |= pair & (discs &>> (3 &* shift))
        return cells
    }

    /// Whether `discs` contains four in a row in any of the four directions.
    @inlinable
    static func hasFour(_ discs: UInt64) -> Bool {
        var pairs = discs & (discs &>> 7)
        if pairs & (pairs &>> 14) != 0 { return true }
        pairs = discs & (discs &>> 6)
        if pairs & (pairs &>> 12) != 0 { return true }
        pairs = discs & (discs &>> 8)
        if pairs & (pairs &>> 16) != 0 { return true }
        pairs = discs & (discs &>> 1)
        return pairs & (pairs &>> 2) != 0
    }

    /// Mirrors a bitboard left to right.
    static func mirrored(_ bits: UInt64) -> UInt64 {
        var result: UInt64 = 0
        for column in 0..<7 {
            let columnBits = (bits &>> (column * 7)) & 0x7F
            result |= columnBits &<< ((6 - column) * 7)
        }
        return result
    }
}
