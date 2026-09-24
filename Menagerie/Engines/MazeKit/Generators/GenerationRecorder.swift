/// Applies a generator's edits to a working grid and records each one as a
/// ``MazeGeneration/Step``.
struct GenerationRecorder {
    /// The grid the recording starts from.
    let initial: MazeGrid
    /// The grid with every recorded step applied.
    private(set) var grid: MazeGrid
    private(set) var steps: [MazeGeneration.Step] = []

    init(_ grid: MazeGrid) {
        initial = grid
        self.grid = grid
    }

    /// Changes a cell's terrain. A step is recorded only if the terrain actually changes.
    mutating func set(_ point: MazePoint, to terrain: MazeCell) {
        guard grid[point] != terrain else { return }
        grid[point] = terrain
        steps.append(.set(point, terrain))
    }

    mutating func mark(_ point: MazePoint) {
        steps.append(.mark(point))
    }

    mutating func unmark(_ point: MazePoint) {
        steps.append(.unmark(point))
    }
}

/// The rooms of a block maze: the cells at odd coordinates. Perfect-maze
/// generators join rooms by opening the wall cell between two neighbours.
/// Rooms are numbered in row-major order.
struct RoomLattice {
    let columns: Int
    let rows: Int

    init(width: Int, height: Int) {
        columns = (width - 1) / 2
        rows = (height - 1) / 2
    }

    var count: Int { columns * rows }

    /// A solid grid with every room open: the starting state for Kruskal's
    /// algorithm, in which every room is its own tree.
    static func roomsOnly(width: Int, height: Int) -> MazeGrid {
        var grid = MazeGrid(width: width, height: height)
        let lattice = RoomLattice(width: width, height: height)
        for room in 0..<lattice.count {
            grid[lattice.point(of: room)] = .open
        }
        return grid
    }

    func point(of room: Int) -> MazePoint {
        MazePoint(x: 2 * (room % columns) + 1, y: 2 * (room / columns) + 1)
    }

    /// The wall cell between two adjacent rooms.
    func wall(between a: Int, and b: Int) -> MazePoint {
        let first = point(of: a)
        let second = point(of: b)
        return MazePoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    /// Replaces `buffer` with the rooms adjacent to `room`, in the order east, north, west, south.
    func neighbors(of room: Int, into buffer: inout [Int]) {
        buffer.removeAll(keepingCapacity: true)
        let column = room % columns
        let row = room / columns
        if column + 1 < columns { buffer.append(room + 1) }
        if row > 0 { buffer.append(room - columns) }
        if column > 0 { buffer.append(room - 1) }
        if row + 1 < rows { buffer.append(room + columns) }
    }
}
