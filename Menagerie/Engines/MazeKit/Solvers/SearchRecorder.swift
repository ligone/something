/// Collects a search's events and turns its result into a ``SearchTrace``.
struct SearchRecorder {
    let grid: MazeGrid
    let solver: MazeSolver
    private var events: [SearchTrace.Event] = []
    private var expanded = 0
    private var discovered = 0

    init(grid: MazeGrid, solver: MazeSolver) {
        self.grid = grid
        self.solver = solver
        events.reserveCapacity(2 * grid.cellCount)
    }

    mutating func discover(_ cell: Int, fromGoal: Bool = false) {
        discovered += 1
        events.append(SearchTrace.Event(kind: .discovered, point: grid.point(at: cell), fromGoal: fromGoal))
    }

    mutating func expand(_ cell: Int, fromGoal: Bool = false) {
        expanded += 1
        events.append(SearchTrace.Event(kind: .expanded, point: grid.point(at: cell), fromGoal: fromGoal))
    }

    /// Builds the trace. `path` lists cell indices from start to goal; an
    /// empty path means the goal was not reached.
    func finish(path: [Int]) -> SearchTrace {
        let cost = path.dropFirst().reduce(0) { $0 + (grid.cells[$1].stepCost ?? 0) }
        let stats = SearchTrace.Stats(
            nodesExpanded: expanded,
            nodesDiscovered: discovered,
            pathLength: max(0, path.count - 1),
            pathCost: cost,
            foundGoal: !path.isEmpty
        )
        return SearchTrace(solver: solver, events: events, path: path.map { grid.point(at: $0) }, stats: stats)
    }
}

/// Follows parent links from `end` back to a root, whose parent is −1, and
/// returns the chain root first.
func pathFromRoot(to end: Int, parents: [Int]) -> [Int] {
    var path = [end]
    var cell = parents[end]
    while cell >= 0 {
        path.append(cell)
        cell = parents[cell]
    }
    return path.reversed()
}
