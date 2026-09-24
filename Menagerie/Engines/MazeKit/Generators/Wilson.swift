extension PerfectMazeCarver {
    /// Wilson's algorithm.
    ///
    /// It seeds the tree with one random room. From each room outside the
    /// tree, it takes a random walk until the walk touches the tree. Whenever
    /// the walk crosses itself, it erases the loop just formed. It then
    /// grafts the loop-erased path onto the tree. The result is a *uniform*
    /// spanning tree, so every perfect maze of the lattice is equally likely.
    /// The live walk is recorded as marked cells, so erased loops visibly
    /// vanish.
    static func wilson(_ recorder: inout GenerationRecorder, random: inout MazeRandom) {
        let lattice = RoomLattice(width: recorder.grid.width, height: recorder.grid.height)
        guard lattice.count > 0 else { return }

        var inTree = [Bool](repeating: false, count: lattice.count)
        // The position of each room in the current walk, or −1.
        var positionInWalk = [Int](repeating: -1, count: lattice.count)
        var walk: [Int] = []
        var neighbors: [Int] = []
        neighbors.reserveCapacity(4)

        let root = random.uniform(below: lattice.count)
        inTree[root] = true
        recorder.set(lattice.point(of: root), to: .open)

        var origins = Array(0..<lattice.count)
        random.shuffle(&origins)
        for origin in origins where !inTree[origin] {
            walk.removeAll(keepingCapacity: true)
            walk.append(origin)
            positionInWalk[origin] = 0
            recorder.mark(lattice.point(of: origin))

            var current = origin
            while true {
                lattice.neighbors(of: current, into: &neighbors)
                let next = neighbors[random.uniform(below: neighbors.count)]

                if inTree[next] {
                    graft(walk, onto: next, lattice: lattice, recorder: &recorder)
                    for room in walk {
                        inTree[room] = true
                        positionInWalk[room] = -1
                    }
                    break
                }

                if positionInWalk[next] >= 0 {
                    // The walk has crossed itself, so erase the loop back to `next`.
                    while walk.count > positionInWalk[next] + 1 {
                        let dropped = walk.removeLast()
                        positionInWalk[dropped] = -1
                        recorder.unmark(lattice.point(of: dropped))
                        recorder.unmark(lattice.wall(between: dropped, and: walk[walk.count - 1]))
                    }
                } else {
                    recorder.mark(lattice.wall(between: current, and: next))
                    recorder.mark(lattice.point(of: next))
                    positionInWalk[next] = walk.count
                    walk.append(next)
                }
                current = next
            }
        }
    }

    /// Carves a loop-erased walk into the maze, from its origin up to the tree room it reached.
    private static func graft(
        _ walk: [Int],
        onto treeRoom: Int,
        lattice: RoomLattice,
        recorder: inout GenerationRecorder
    ) {
        for (position, room) in walk.enumerated() {
            let isLast = position == walk.count - 1
            let successor = isLast ? treeRoom : walk[position + 1]
            let wall = lattice.wall(between: room, and: successor)
            recorder.unmark(lattice.point(of: room))
            recorder.set(lattice.point(of: room), to: .open)
            if !isLast { recorder.unmark(wall) }
            recorder.set(wall, to: .open)
        }
    }
}
