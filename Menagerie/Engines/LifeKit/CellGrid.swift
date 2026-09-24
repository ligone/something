/// The shape of the uniform grid used for neighbor search.
///
/// Cells are at least one interaction radius wide, so every neighbor of a
/// particle lies in the 3 × 3 block of cells around its own. When the domain
/// is too small for that block to hold nine distinct cells, the grid collapses
/// to a single cell and pairs are compared directly.
struct CellGrid: Equatable {
    let columns: Int
    let rows: Int
    let cellWidth: Float
    let cellHeight: Float

    /// Bounds the grid so a tiny radius cannot demand millions of cells.
    static let maximumCellsPerSide = 512

    init(domain: TorusDomain, radius: Float) {
        func cellsFitting(_ extent: Float) -> Int {
            let fitting = (extent / radius).rounded(.down)
            return Int(min(max(fitting, 1), Float(Self.maximumCellsPerSide)))
        }
        var columns = cellsFitting(domain.width)
        var rows = cellsFitting(domain.height)
        if columns < 3 || rows < 3 {
            columns = 1
            rows = 1
        }
        self.columns = columns
        self.rows = rows
        self.cellWidth = domain.width / Float(columns)
        self.cellHeight = domain.height / Float(rows)
    }

    var cellCount: Int { columns * rows }

    /// A single cell: pairs must be compared by minimum image.
    var isSingleCell: Bool { columns == 1 }

    /// The cell holding a point inside the domain.
    @inline(__always)
    func cell(x: Float, y: Float) -> Int {
        column(for: x) + row(for: y) * columns
    }

    @inline(__always)
    private func column(for x: Float) -> Int {
        let scaled = x / cellWidth
        // The comparisons also catch NaN, which must never reach `Int(_:)`.
        guard scaled >= 0 else { return 0 }
        return scaled < Float(columns) ? min(Int(scaled), columns - 1) : columns - 1
    }

    @inline(__always)
    private func row(for y: Float) -> Int {
        let scaled = y / cellHeight
        guard scaled >= 0 else { return 0 }
        return scaled < Float(rows) ? min(Int(scaled), rows - 1) : rows - 1
    }

    /// Visits every run of cell-sorted particles in the 3 × 3 neighborhood of
    /// `cell`.
    ///
    /// Horizontally adjacent cells are stored back to back, so each row of the
    /// neighborhood is one contiguous run unless it crosses the left or right
    /// seam. `body` receives the run's bounds and the offset that moves those
    /// particles next to `cell` across any seam, which spares the inner loop
    /// a minimum-image test per pair. Requires a grid of at least 3 × 3 cells.
    @inline(__always)
    func forEachNeighborRun(
        of cell: Int,
        cellStart: UnsafePointer<Int32>,
        domain: TorusDomain,
        _ body: (_ start: Int, _ end: Int, _ shiftX: Float, _ shiftY: Float) -> Void
    ) {
        let cellRow = cell / columns
        let cellColumn = cell - cellRow * columns
        for rowOffset in -1...1 {
            var row = cellRow + rowOffset
            var shiftY: Float = 0
            if row < 0 {
                row += rows
                shiftY = -domain.height
            } else if row >= rows {
                row -= rows
                shiftY = domain.height
            }
            let first = row * columns
            if cellColumn == 0 {
                body(Int(cellStart[first]), Int(cellStart[first + 2]), 0, shiftY)
                body(Int(cellStart[first + columns - 1]), Int(cellStart[first + columns]), -domain.width, shiftY)
            } else if cellColumn == columns - 1 {
                body(Int(cellStart[first + columns - 2]), Int(cellStart[first + columns]), 0, shiftY)
                body(Int(cellStart[first]), Int(cellStart[first + 1]), domain.width, shiftY)
            } else {
                body(Int(cellStart[first + cellColumn - 1]), Int(cellStart[first + cellColumn + 2]), 0, shiftY)
            }
        }
    }
}
