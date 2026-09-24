extension PerfectMazeCarver {
    /// Randomized Prim's algorithm.
    ///
    /// Keeps a frontier of rooms next to the maze. It repeatedly takes a
    /// random frontier room, joins it to a random neighbour already in the
    /// maze, and adds that room's new neighbours to the frontier. Frontier
    /// rooms are recorded as marked cells.
    static func prim(_ recorder: inout GenerationRecorder, random: inout MazeRandom) {
        let lattice = RoomLattice(width: recorder.grid.width, height: recorder.grid.height)
        guard lattice.count > 0 else { return }

        var inMaze = [Bool](repeating: false, count: lattice.count)
        var inFrontier = [Bool](repeating: false, count: lattice.count)
        var frontier: [Int] = []
        var neighbors: [Int] = []
        var links: [Int] = []
        neighbors.reserveCapacity(4)
        links.reserveCapacity(4)

        var room = random.uniform(below: lattice.count)
        inMaze[room] = true
        recorder.set(lattice.point(of: room), to: .open)

        while true {
            // Admit the newest room's outside neighbours to the frontier.
            lattice.neighbors(of: room, into: &neighbors)
            for neighbor in neighbors where !inMaze[neighbor] && !inFrontier[neighbor] {
                inFrontier[neighbor] = true
                frontier.append(neighbor)
                recorder.mark(lattice.point(of: neighbor))
            }
            guard !frontier.isEmpty else { return }

            // Join a random frontier room to a random neighbour inside the maze.
            frontier.swapAt(random.uniform(below: frontier.count), frontier.count - 1)
            room = frontier.removeLast()
            inFrontier[room] = false
            lattice.neighbors(of: room, into: &neighbors)
            links.removeAll(keepingCapacity: true)
            for neighbor in neighbors where inMaze[neighbor] {
                links.append(neighbor)
            }
            let link = links[random.uniform(below: links.count)]
            recorder.unmark(lattice.point(of: room))
            recorder.set(lattice.wall(between: room, and: link), to: .open)
            recorder.set(lattice.point(of: room), to: .open)
            inMaze[room] = true
        }
    }
}
