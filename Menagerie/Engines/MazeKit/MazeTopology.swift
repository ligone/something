/// The graph structure of a maze's passable cells, where two passable cells
/// are connected when they are orthogonal neighbours.
public struct MazeTopology: Hashable, Sendable {
    /// The number of passable cells, which are the graph's vertices.
    public let passableCells: Int
    /// The number of adjacent pairs of passable cells, which are the graph's edges.
    public let connections: Int
    /// The number of separate connected regions.
    public let components: Int
    /// The number of passable cells with exactly one passable neighbour.
    public let deadEnds: Int

    /// The cycle rank, `E − V + C`: how many independent loops the passages
    /// contain. A perfect maze has none.
    public var loops: Int { connections - passableCells + components }

    /// Whether the passages form a single spanning tree, with exactly one
    /// route between any two cells.
    public var isPerfect: Bool { passableCells > 0 && components == 1 && loops == 0 }
}

extension MazeGrid {
    /// Counts the cells, connections, regions, loops and dead ends of the maze in O(n).
    public var topology: MazeTopology {
        var regions = DisjointSet(count: cellCount)
        var passable = 0
        var connections = 0
        var merges = 0
        var deadEnds = 0
        for index in cells.indices where cells[index].isPassable {
            passable += 1
            let x = index % width
            if x + 1 < width, cells[index + 1].isPassable {
                connections += 1
                if regions.union(index, index + 1) { merges += 1 }
            }
            if index + width < cellCount, cells[index + width].isPassable {
                connections += 1
                if regions.union(index, index + width) { merges += 1 }
            }
            if passableDegree(ofIndex: index) == 1 { deadEnds += 1 }
        }
        return MazeTopology(
            passableCells: passable,
            connections: connections,
            components: passable - merges,
            deadEnds: deadEnds
        )
    }

    /// Flags every cell reachable from `origin` through passable cells,
    /// indexed like ``cells``. Nothing is reachable from an impassable origin.
    public func reachableCells(from origin: MazePoint) -> [Bool] {
        var reached = [Bool](repeating: false, count: cellCount)
        guard isPassable(origin) else { return reached }
        let first = index(of: origin)
        reached[first] = true
        var queue = [first]
        var head = 0
        var neighbors: [Int] = []
        neighbors.reserveCapacity(4)
        while head < queue.count {
            let current = queue[head]
            head += 1
            passableNeighbors(ofIndex: current, into: &neighbors)
            for next in neighbors where !reached[next] {
                reached[next] = true
                queue.append(next)
            }
        }
        return reached
    }

    /// Whether some route of passable cells connects the two points.
    public func isReachable(_ target: MazePoint, from origin: MazePoint) -> Bool {
        guard contains(target), isPassable(target) else { return false }
        return reachableCells(from: origin)[index(of: target)]
    }
}
