extension PerfectMazeCarver {
    /// Randomized Kruskal's algorithm.
    ///
    /// Every room starts as its own tree. It visits the walls between rooms
    /// in random order and opens a wall only when the rooms on either side
    /// belong to different trees, which it checks with union–find. That rule
    /// makes loops impossible. It stops after `rooms − 1` openings, when a
    /// single spanning tree remains. The recorder must start from
    /// ``RoomLattice/roomsOnly(width:height:)``.
    static func kruskal(_ recorder: inout GenerationRecorder, random: inout MazeRandom) {
        let lattice = RoomLattice(width: recorder.grid.width, height: recorder.grid.height)
        guard lattice.count > 1 else { return }

        var walls: [(Int, Int)] = []
        walls.reserveCapacity(2 * lattice.count)
        for room in 0..<lattice.count {
            if room % lattice.columns + 1 < lattice.columns { walls.append((room, room + 1)) }
            if room / lattice.columns + 1 < lattice.rows { walls.append((room, room + lattice.columns)) }
        }
        random.shuffle(&walls)

        var trees = DisjointSet(count: lattice.count)
        var openings = 0
        for (a, b) in walls {
            guard trees.union(a, b) else { continue }
            recorder.set(lattice.wall(between: a, and: b), to: .open)
            openings += 1
            if openings == lattice.count - 1 { return }
        }
    }
}
