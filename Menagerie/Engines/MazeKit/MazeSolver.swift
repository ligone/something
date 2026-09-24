/// The path-finding algorithms. Each returns a complete ``SearchTrace``.
public enum MazeSolver: String, CaseIterable, Identifiable, Sendable {
    /// Breadth-first search: expands in rings and finds the path with the fewest steps.
    case breadthFirst
    /// Depth-first search: dives down one corridor at a time. It finds *a*
    /// path, but usually a poor one.
    case depthFirst
    /// Dijkstra's algorithm: expands the cheapest cell first from a binary heap,
    /// so it finds the cheapest path through mud.
    case dijkstra
    /// A*: Dijkstra plus the Manhattan-distance heuristic. It finds the same
    /// cheapest cost while expanding far fewer cells.
    case aStar
    /// Greedy best-first search: follows the heuristic alone. It is fast but
    /// can be fooled.
    case greedyBestFirst
    /// Two breadth-first searches, one from each end, that stop when their
    /// frontiers meet. It finds the fewest-step path.
    case bidirectional

    public var id: String { rawValue }

    /// A display name.
    public var name: String {
        switch self {
        case .breadthFirst: return "Breadth-first"
        case .depthFirst: return "Depth-first"
        case .dijkstra: return "Dijkstra"
        case .aStar: return "A*"
        case .greedyBestFirst: return "Greedy best-first"
        case .bidirectional: return "Bidirectional BFS"
        }
    }

    /// A compact name for charts and tables.
    public var shortName: String {
        switch self {
        case .breadthFirst: return "BFS"
        case .depthFirst: return "DFS"
        case .dijkstra: return "Dijkstra"
        case .aStar: return "A*"
        case .greedyBestFirst: return "Greedy"
        case .bidirectional: return "Bi-BFS"
        }
    }

    /// A one-line description of the search.
    public var summary: String {
        switch self {
        case .breadthFirst: return "Expands in rings from the start. Fewest steps, blind to mud."
        case .depthFirst: return "Dives down one corridor at a time. Finds a path, rarely a good one."
        case .dijkstra: return "Always expands the cheapest cell, so it detours around mud."
        case .aStar: return "Dijkstra steered by Manhattan distance: just as cheap, far fewer cells."
        case .greedyBestFirst: return "Chases the goal by distance alone. Quick, but easily fooled."
        case .bidirectional: return "Two breadth-first waves, one from each end, meet in the middle."
        }
    }

    /// Whether the search weighs mud by its cost. The others treat every step alike.
    public var respectsTerrainCost: Bool {
        self == .dijkstra || self == .aStar
    }

    /// Whether the search guarantees an optimal path: the cheapest one for
    /// weighted searches, and the fewest steps for the others.
    public var isOptimal: Bool {
        switch self {
        case .depthFirst, .greedyBestFirst: return false
        default: return true
        }
    }

    /// Runs the search on a grid from its start to its goal. An impassable
    /// start or goal, or one outside the grid, yields an empty trace that
    /// reports the goal as not found.
    public func solve(_ grid: MazeGrid) -> SearchTrace {
        guard grid.isPassable(grid.start), grid.isPassable(grid.goal) else {
            return SearchRecorder(grid: grid, solver: self).finish(path: [])
        }
        switch self {
        case .breadthFirst: return UninformedSearch.breadthFirst(grid)
        case .depthFirst: return UninformedSearch.depthFirst(grid)
        case .dijkstra: return BestFirstSearch.run(grid, strategy: .dijkstra)
        case .aStar: return BestFirstSearch.run(grid, strategy: .aStar)
        case .greedyBestFirst: return BestFirstSearch.run(grid, strategy: .greedy)
        case .bidirectional: return BidirectionalSearch.run(grid)
        }
    }

    /// Runs every solver on the same grid, in ``allCases`` order.
    public static func solveAll(_ grid: MazeGrid) -> [SearchTrace] {
        allCases.map { $0.solve(grid) }
    }
}
