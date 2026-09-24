/// The terrain of one cell of a ``MazeGrid``.
///
/// MazeKit uses the *block maze* representation, in which walls occupy whole
/// cells. A carved maze, a recursive-division maze and a hand-painted
/// obstacle course therefore all share one model.
public enum MazeCell: UInt8, CaseIterable, Hashable, Sendable {
    /// An impassable cell.
    case wall
    /// Open floor. Stepping onto it costs 1.
    case open
    /// Passable but slow. Stepping onto it costs ``MazeCell/mudCost``.
    case mud

    /// The cost of stepping onto mud. Open floor costs 1.
    public static let mudCost = 5

    /// Whether a search may enter the cell.
    public var isPassable: Bool { self != .wall }

    /// The cost of stepping *onto* the cell, or `nil` for a wall.
    public var stepCost: Int? {
        switch self {
        case .wall: return nil
        case .open: return 1
        case .mud: return MazeCell.mudCost
        }
    }
}

/// A cell coordinate. `x` counts columns from the left and `y` counts rows
/// from the top, matching screen coordinates.
public struct MazePoint: Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// The number of orthogonal steps between two points, ignoring walls.
    public func manhattanDistance(to other: MazePoint) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }

    /// Whether `other` is exactly one orthogonal step away.
    public func isAdjacent(to other: MazePoint) -> Bool {
        manhattanDistance(to: other) == 1
    }

    public var description: String { "(\(x), \(y))" }

    func offset(_ direction: MazeDirection, by distance: Int = 1) -> MazePoint {
        MazePoint(x: x + direction.dx * distance, y: y + direction.dy * distance)
    }
}

/// The four orthogonal directions, in the fixed order every algorithm in
/// MazeKit visits neighbours: east, north, west, south.
///
/// A fixed order keeps every search deterministic. It also makes depth-first
/// search sweep an open field row by row, which shows vividly how far from
/// optimal its paths can be.
enum MazeDirection: CaseIterable {
    case east, north, west, south

    var dx: Int {
        switch self {
        case .east: return 1
        case .west: return -1
        case .north, .south: return 0
        }
    }

    var dy: Int {
        switch self {
        case .south: return 1
        case .north: return -1
        case .east, .west: return 0
        }
    }
}
