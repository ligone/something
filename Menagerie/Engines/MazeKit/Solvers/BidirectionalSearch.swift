/// Bidirectional breadth-first search.
enum BidirectionalSearch {
    /// Grows one breadth-first search from the start and one from the goal,
    /// expanding a *whole layer* at a time on whichever side has the smaller
    /// frontier. The first cell that one side discovers and the other has
    /// already seen joins the two trees.
    ///
    /// Expanding whole layers is what makes that first meeting optimal. While
    /// no cell is shared, the forward ball of radius `a` and the backward
    /// ball of radius `b` are disjoint, so the shortest path has at least
    /// `a + b + 1` steps. The first meeting yields a path of at most
    /// `a + b + 1` steps, so it is a shortest path. If single cells were
    /// expanded in alternation, the answer could be one step too long.
    static func run(_ grid: MazeGrid) -> SearchTrace {
        var recorder = SearchRecorder(grid: grid, solver: .bidirectional)
        let start = grid.index(of: grid.start)
        let goal = grid.index(of: grid.goal)
        recorder.discover(start)
        guard start != goal else {
            recorder.expand(start)
            return recorder.finish(path: [start])
        }
        recorder.discover(goal, fromGoal: true)

        var forwardParent = [Int](repeating: -1, count: grid.cellCount)
        var backwardParent = [Int](repeating: -1, count: grid.cellCount)
        var seenForward = [Bool](repeating: false, count: grid.cellCount)
        var seenBackward = [Bool](repeating: false, count: grid.cellCount)
        seenForward[start] = true
        seenBackward[goal] = true
        var forwardLayer = [start]
        var backwardLayer = [goal]
        var nextLayer: [Int] = []
        var neighbors: [Int] = []
        neighbors.reserveCapacity(4)

        while !forwardLayer.isEmpty && !backwardLayer.isEmpty {
            let forward = forwardLayer.count <= backwardLayer.count
            let layer = forward ? forwardLayer : backwardLayer
            nextLayer.removeAll(keepingCapacity: true)
            for cell in layer {
                recorder.expand(cell, fromGoal: !forward)
                grid.passableNeighbors(ofIndex: cell, into: &neighbors)
                for next in neighbors {
                    if forward {
                        guard !seenForward[next] else { continue }
                        seenForward[next] = true
                        forwardParent[next] = cell
                    } else {
                        guard !seenBackward[next] else { continue }
                        seenBackward[next] = true
                        backwardParent[next] = cell
                    }
                    if seenForward[next] && seenBackward[next] {
                        let path = joinedPath(through: next, forwardParent: forwardParent, backwardParent: backwardParent)
                        return recorder.finish(path: path)
                    }
                    recorder.discover(next, fromGoal: !forward)
                    nextLayer.append(next)
                }
            }
            if forward {
                swap(&forwardLayer, &nextLayer)
            } else {
                swap(&backwardLayer, &nextLayer)
            }
        }
        return recorder.finish(path: [])
    }

    /// The start-to-meeting chain from the forward tree, followed by the
    /// meeting-to-goal chain from the backward tree.
    private static func joinedPath(through meeting: Int, forwardParent: [Int], backwardParent: [Int]) -> [Int] {
        var path = pathFromRoot(to: meeting, parents: forwardParent)
        var cell = backwardParent[meeting]
        while cell >= 0 {
            path.append(cell)
            cell = backwardParent[cell]
        }
        return path
    }
}
