/// A rectangular maze: a row-major array of ``MazeCell`` values, plus the
/// cells where searches start and end.
///
/// Generated mazes use odd dimensions. The *rooms* sit at odd coordinates and
/// the cells between them are either wall or passage, while the outer ring is
/// always wall. Searches treat any grid the same way, so the user can paint
/// walls and mud freely on top of a generated maze.
public struct MazeGrid: Hashable, Sendable {
    /// The number of columns.
    public let width: Int
    /// The number of rows.
    public let height: Int
    /// Every cell in row-major order. Use ``index(of:)`` to locate a point.
    public private(set) var cells: [MazeCell]
    /// Where searches begin.
    public var start: MazePoint
    /// Where searches try to reach.
    public var goal: MazePoint

    /// Creates a grid in which every cell has the same terrain. The start is
    /// the top-left interior cell and the goal is the bottom-right one.
    public init(width: Int, height: Int, filledWith fill: MazeCell = .wall) {
        precondition(width >= 3 && height >= 3, "A MazeGrid needs at least 3 × 3 cells")
        self.width = width
        self.height = height
        self.cells = Array(repeating: fill, count: width * height)
        self.start = MazePoint(x: 1, y: 1)
        self.goal = MazePoint(x: width - 2, y: height - 2)
    }

    /// An open field: a ring of wall around open floor.
    public static func openField(width: Int, height: Int) -> MazeGrid {
        var grid = MazeGrid(width: width, height: height, filledWith: .open)
        for x in 0..<width {
            grid.cells[x] = .wall
            grid.cells[(height - 1) * width + x] = .wall
        }
        for y in 0..<height {
            grid.cells[y * width] = .wall
            grid.cells[y * width + width - 1] = .wall
        }
        return grid
    }

    /// Builds a grid from a picture with one string per row. `#` is wall, `.`
    /// is open floor and `~` is mud. `S` and `G` mark the start and goal,
    /// which both stand on open floor.
    ///
    /// Returns `nil` when the rows are ragged, the picture is smaller than
    /// 3 × 3, or it contains any other character.
    public init?(ascii rows: [String]) {
        guard rows.count >= 3, let columns = rows.first?.count, columns >= 3,
              rows.allSatisfy({ $0.count == columns })
        else { return nil }
        self.init(width: columns, height: rows.count)
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() {
                let point = MazePoint(x: x, y: y)
                switch character {
                case "#": self[point] = .wall
                case ".": self[point] = .open
                case "~": self[point] = .mud
                case "S":
                    self[point] = .open
                    start = point
                case "G":
                    self[point] = .open
                    goal = point
                default:
                    return nil
                }
            }
        }
    }

    /// The grid drawn with the characters that ``init(ascii:)`` reads.
    public var asciiRows: [String] {
        (0..<height).map { y in
            String((0..<width).map { x -> Character in
                let point = MazePoint(x: x, y: y)
                if point == start { return "S" }
                if point == goal { return "G" }
                switch self[point] {
                case .wall: return "#"
                case .open: return "."
                case .mud: return "~"
                }
            })
        }
    }

    // MARK: Coordinates

    /// The total number of cells, `width × height`.
    public var cellCount: Int { cells.count }

    /// Whether the point lies inside the grid.
    public func contains(_ point: MazePoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x < width && point.y < height
    }

    /// Whether the point lies on the outermost ring of cells.
    public func isOnBorder(_ point: MazePoint) -> Bool {
        contains(point) && (point.x == 0 || point.y == 0 || point.x == width - 1 || point.y == height - 1)
    }

    /// The position of a point in ``cells``.
    public func index(of point: MazePoint) -> Int {
        point.y * width + point.x
    }

    /// The point stored at a position in ``cells``.
    public func point(at index: Int) -> MazePoint {
        MazePoint(x: index % width, y: index / width)
    }

    // MARK: Terrain

    /// The terrain at a point. Points outside the grid read as walls.
    public subscript(point: MazePoint) -> MazeCell {
        get { contains(point) ? cells[index(of: point)] : .wall }
        set {
            precondition(contains(point), "\(point) lies outside the \(width) × \(height) grid")
            cells[index(of: point)] = newValue
        }
    }

    /// The terrain at column `x`, row `y`. Points outside the grid read as walls.
    public subscript(x x: Int, y y: Int) -> MazeCell {
        get { self[MazePoint(x: x, y: y)] }
        set { self[MazePoint(x: x, y: y)] = newValue }
    }

    /// Whether a search may enter the point. Points outside the grid are impassable.
    public func isPassable(_ point: MazePoint) -> Bool {
        self[point].isPassable
    }

    /// The passable cells one orthogonal step away, in the order east, north, west, south.
    public func passableNeighbors(of point: MazePoint) -> [MazePoint] {
        MazeDirection.allCases.map { point.offset($0) }.filter { isPassable($0) }
    }

    /// How many cells have the given terrain.
    public func count(of terrain: MazeCell) -> Int {
        cells.reduce(0) { $0 + ($1 == terrain ? 1 : 0) }
    }

    /// Replays one generation step. Only ``MazeGeneration/Step/set(_:_:)``
    /// changes the grid; marks are purely visual.
    public mutating func apply(_ step: MazeGeneration.Step) {
        if case let .set(point, terrain) = step {
            self[point] = terrain
        }
    }

    // MARK: Internal fast paths

    /// Replaces `buffer` with the indices of the passable cells orthogonally
    /// adjacent to `index`, in the order east, north, west, south.
    func passableNeighbors(ofIndex index: Int, into buffer: inout [Int]) {
        buffer.removeAll(keepingCapacity: true)
        let x = index % width
        let y = index / width
        if x + 1 < width, cells[index + 1].isPassable { buffer.append(index + 1) }
        if y > 0, cells[index - width].isPassable { buffer.append(index - width) }
        if x > 0, cells[index - 1].isPassable { buffer.append(index - 1) }
        if y + 1 < height, cells[index + width].isPassable { buffer.append(index + width) }
    }

    /// The number of passable cells orthogonally adjacent to `index`.
    func passableDegree(ofIndex index: Int) -> Int {
        let x = index % width
        let y = index / width
        var degree = 0
        if x + 1 < width, cells[index + 1].isPassable { degree += 1 }
        if y > 0, cells[index - width].isPassable { degree += 1 }
        if x > 0, cells[index - 1].isPassable { degree += 1 }
        if y + 1 < height, cells[index + width].isPassable { degree += 1 }
        return degree
    }
}
