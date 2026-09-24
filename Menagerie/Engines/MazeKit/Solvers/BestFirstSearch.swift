/// Dijkstra's algorithm, A* and greedy best-first search. All three share
/// one loop over a binary-heap frontier and differ only in how they rank
/// entries.
enum BestFirstSearch {
    enum Strategy {
        /// Ranks by path cost so far, `g`. Ties go first-in, first-out, which
        /// grows tidy rings on uniform ground.
        case dijkstra
        /// Ranks by `f = g + h`, where `h` is the Manhattan distance to the
        /// goal. Ties go to the smaller `h`, which is the larger `g`, and then
        /// to the newest entry. That keeps the search pressing toward the goal
        /// instead of flooding a plateau of equal `f`.
        case aStar
        /// Ranks by `h` alone. Ties go to the newest entry.
        case greedy
    }

    /// A frontier entry. Entries compare by priority, then tie-break, then order.
    struct Entry: Comparable {
        var priority: Int
        var tieBreak: Int
        var order: Int
        var cell: Int
        var cost: Int

        static func < (lhs: Entry, rhs: Entry) -> Bool {
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            if lhs.tieBreak != rhs.tieBreak { return lhs.tieBreak < rhs.tieBreak }
            return lhs.order < rhs.order
        }
    }

    /// Runs the search. With A*, the Manhattan heuristic is *consistent*,
    /// because every step costs at least 1 and moves exactly one cell. So the
    /// first time a cell is expanded, its cost is already optimal, and A*
    /// reaches the goal at the same cost as Dijkstra.
    static func run(_ grid: MazeGrid, strategy: Strategy) -> SearchTrace {
        let solver: MazeSolver
        switch strategy {
        case .dijkstra: solver = .dijkstra
        case .aStar: solver = .aStar
        case .greedy: solver = .greedyBestFirst
        }
        var recorder = SearchRecorder(grid: grid, solver: solver)
        let start = grid.index(of: grid.start)
        let goal = grid.index(of: grid.goal)
        let width = grid.width
        let goalX = grid.goal.x
        let goalY = grid.goal.y

        var bestCost = [Int](repeating: .max, count: grid.cellCount)
        var parent = [Int](repeating: -1, count: grid.cellCount)
        var closed = [Bool](repeating: false, count: grid.cellCount)
        var frontier = MazePriorityQueue<Entry>()
        frontier.reserveCapacity(grid.cellCount)
        var neighbors: [Int] = []
        neighbors.reserveCapacity(4)
        var sequence = 0

        func entry(_ cell: Int, cost: Int) -> Entry {
            sequence += 1
            let h = abs(cell % width - goalX) + abs(cell / width - goalY)
            switch strategy {
            case .dijkstra:
                return Entry(priority: cost, tieBreak: 0, order: sequence, cell: cell, cost: cost)
            case .aStar:
                return Entry(priority: cost + h, tieBreak: h, order: -sequence, cell: cell, cost: cost)
            case .greedy:
                return Entry(priority: h, tieBreak: 0, order: -sequence, cell: cell, cost: cost)
            }
        }

        bestCost[start] = 0
        frontier.push(entry(start, cost: 0))
        recorder.discover(start)
        while let current = frontier.pop() {
            let cell = current.cell
            // Skip entries left behind when a cheaper route to the cell was found.
            guard !closed[cell], current.cost <= bestCost[cell] else { continue }
            closed[cell] = true
            recorder.expand(cell)
            if cell == goal {
                return recorder.finish(path: pathFromRoot(to: goal, parents: parent))
            }
            grid.passableNeighbors(ofIndex: cell, into: &neighbors)
            for next in neighbors where !closed[next] {
                let isNew = bestCost[next] == .max
                let cost = current.cost + (grid.cells[next].stepCost ?? 0)
                // Greedy search never revises a cell once it has been queued;
                // the other two do whenever they find a cheaper route.
                guard strategy == .greedy ? isNew : cost < bestCost[next] else { continue }
                bestCost[next] = cost
                parent[next] = cell
                frontier.push(entry(next, cost: cost))
                if isNew { recorder.discover(next) }
            }
        }
        return recorder.finish(path: [])
    }
}
