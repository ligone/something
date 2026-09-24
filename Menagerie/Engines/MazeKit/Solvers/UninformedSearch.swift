/// Searches that know nothing about where the goal is.
enum UninformedSearch {
    /// Breadth-first search with a FIFO queue. It visits cells in rings of
    /// equal step count, so the first time it expands the goal it has found a
    /// path with the fewest steps.
    static func breadthFirst(_ grid: MazeGrid) -> SearchTrace {
        var recorder = SearchRecorder(grid: grid, solver: .breadthFirst)
        let start = grid.index(of: grid.start)
        let goal = grid.index(of: grid.goal)
        var parent = [Int](repeating: -1, count: grid.cellCount)
        var seen = [Bool](repeating: false, count: grid.cellCount)
        var queue = [start]
        queue.reserveCapacity(grid.cellCount)
        var head = 0
        var neighbors: [Int] = []
        neighbors.reserveCapacity(4)

        seen[start] = true
        recorder.discover(start)
        while head < queue.count {
            let cell = queue[head]
            head += 1
            recorder.expand(cell)
            if cell == goal {
                return recorder.finish(path: pathFromRoot(to: goal, parents: parent))
            }
            grid.passableNeighbors(ofIndex: cell, into: &neighbors)
            for next in neighbors where !seen[next] {
                seen[next] = true
                parent[next] = cell
                queue.append(next)
                recorder.discover(next)
            }
        }
        return recorder.finish(path: [])
    }

    /// Depth-first search with a LIFO stack. A cell's parent is fixed when the
    /// cell is expanded, so the path follows the true depth-first tree: the
    /// corridor DFS happened to be exploring when it stumbled on the goal.
    static func depthFirst(_ grid: MazeGrid) -> SearchTrace {
        var recorder = SearchRecorder(grid: grid, solver: .depthFirst)
        let start = grid.index(of: grid.start)
        let goal = grid.index(of: grid.goal)
        var parent = [Int](repeating: -1, count: grid.cellCount)
        var expanded = [Bool](repeating: false, count: grid.cellCount)
        var discovered = [Bool](repeating: false, count: grid.cellCount)
        var stack: [(cell: Int, parent: Int)] = [(start, -1)]
        var neighbors: [Int] = []
        neighbors.reserveCapacity(4)

        discovered[start] = true
        recorder.discover(start)
        while let entry = stack.popLast() {
            guard !expanded[entry.cell] else { continue }
            expanded[entry.cell] = true
            parent[entry.cell] = entry.parent
            recorder.expand(entry.cell)
            if entry.cell == goal {
                return recorder.finish(path: pathFromRoot(to: goal, parents: parent))
            }
            grid.passableNeighbors(ofIndex: entry.cell, into: &neighbors)
            // Push in reverse, so the first neighbour in east-north-west-south order is explored first.
            for next in neighbors.reversed() where !expanded[next] {
                stack.append((next, entry.cell))
                if !discovered[next] {
                    discovered[next] = true
                    recorder.discover(next)
                }
            }
        }
        return recorder.finish(path: [])
    }
}
