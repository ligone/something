/// The algorithms that carve perfect mazes: spanning trees over the room lattice.
enum PerfectMazeCarver {}

extension PerfectMazeCarver {
    /// Randomized depth-first search with an explicit stack.
    ///
    /// From the room on top of the stack, it opens the wall to a random
    /// unvisited neighbour and pushes that neighbour. When the top room has no
    /// unvisited neighbours, it pops. The stack is recorded as marked cells,
    /// so the trail visibly extends and retracts.
    static func recursiveBacktracker(_ recorder: inout GenerationRecorder, random: inout MazeRandom) {
        let lattice = RoomLattice(width: recorder.grid.width, height: recorder.grid.height)
        guard lattice.count > 0 else { return }

        var visited = [Bool](repeating: false, count: lattice.count)
        var candidates: [Int] = []
        candidates.reserveCapacity(4)

        let first = random.uniform(below: lattice.count)
        visited[first] = true
        recorder.set(lattice.point(of: first), to: .open)
        recorder.mark(lattice.point(of: first))

        // Each entry remembers the wall it was entered through, so that
        // backtracking can clear the whole trail.
        var stack: [(room: Int, entrance: MazePoint?)] = [(first, nil)]
        while let top = stack.last {
            lattice.neighbors(of: top.room, into: &candidates)
            candidates.removeAll { visited[$0] }
            guard !candidates.isEmpty else {
                stack.removeLast()
                recorder.unmark(lattice.point(of: top.room))
                if let entrance = top.entrance { recorder.unmark(entrance) }
                continue
            }
            let next = candidates[random.uniform(below: candidates.count)]
            visited[next] = true
            let wall = lattice.wall(between: top.room, and: next)
            recorder.set(wall, to: .open)
            recorder.mark(wall)
            recorder.set(lattice.point(of: next), to: .open)
            recorder.mark(lattice.point(of: next))
            stack.append((next, wall))
        }
    }
}
