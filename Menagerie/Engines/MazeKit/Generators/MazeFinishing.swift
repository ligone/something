/// Passes that run after any generator: spreading mud and braiding in loops.
enum MazeFinishing {
    /// Covers about `coverage` of the interior floor with organic mud patches
    /// of 4 to 12 cells. Each patch grows from a random seed cell by absorbing
    /// random frontier cells. The start and goal never become mud.
    static func spreadMud(_ recorder: inout GenerationRecorder, coverage: Double, random: inout MazeRandom) {
        let coverage = min(max(coverage, 0), 1)
        guard coverage > 0 else { return }

        let grid = recorder.grid
        let startIndex = grid.index(of: grid.start)
        let goalIndex = grid.index(of: grid.goal)
        let floor = grid.cells.indices.filter { index in
            grid.cells[index] == .open && index != startIndex && index != goalIndex
                && !grid.isOnBorder(grid.point(at: index))
        }
        guard !floor.isEmpty else { return }

        let target = Int((Double(floor.count) * coverage).rounded())
        // Stamps the patch number on queued cells, so they needn't be cleared between patches.
        var queuedInPatch = [Int](repeating: -1, count: grid.cellCount)
        var frontier: [Int] = []
        var neighbors: [Int] = []
        var covered = 0
        var patch = 0
        while covered < target && patch < floor.count {
            patch += 1
            let seed = floor[random.uniform(below: floor.count)]
            guard recorder.grid.cells[seed] == .open else { continue }
            let patchSize = 4 + random.uniform(below: 9)
            var grown = 0
            frontier.removeAll(keepingCapacity: true)
            frontier.append(seed)
            queuedInPatch[seed] = patch
            while !frontier.isEmpty && grown < patchSize && covered < target {
                frontier.swapAt(random.uniform(below: frontier.count), frontier.count - 1)
                let cell = frontier.removeLast()
                let point = recorder.grid.point(at: cell)
                guard recorder.grid.cells[cell] == .open, cell != startIndex, cell != goalIndex,
                      !recorder.grid.isOnBorder(point)
                else { continue }
                recorder.set(point, to: .mud)
                grown += 1
                covered += 1
                recorder.grid.passableNeighbors(ofIndex: cell, into: &neighbors)
                for neighbor in neighbors where queuedInPatch[neighbor] != patch && recorder.grid.cells[neighbor] == .open {
                    queuedInPatch[neighbor] = patch
                    frontier.append(neighbor)
                }
            }
        }
    }

    /// Knocks a `fraction` of the dead ends through into a neighbouring
    /// passage. Each knock-through closes a loop.
    ///
    /// Following Jamis Buck's braiding, a dead end prefers to open toward
    /// another dead end, which clears two at once. The dead ends are shuffled
    /// once and then handled as a prefix of that order, so a larger fraction
    /// always opens a superset of the walls a smaller one opens.
    static func braid(_ recorder: inout GenerationRecorder, fraction: Double, random: inout MazeRandom) {
        let fraction = min(max(fraction, 0), 1)
        guard fraction > 0 else { return }

        let grid = recorder.grid
        var deadEnds = grid.cells.indices.filter { index in
            grid.cells[index].isPassable && grid.passableDegree(ofIndex: index) == 1
        }
        random.shuffle(&deadEnds)
        let quota = Int((Double(deadEnds.count) * fraction).rounded())

        var preferred: [MazePoint] = []
        var fallback: [MazePoint] = []
        for cell in deadEnds.prefix(quota) {
            // An earlier knock-through may already have opened this dead end.
            guard recorder.grid.passableDegree(ofIndex: cell) == 1 else { continue }
            let point = recorder.grid.point(at: cell)
            preferred.removeAll(keepingCapacity: true)
            fallback.removeAll(keepingCapacity: true)
            for direction in MazeDirection.allCases {
                let wall = point.offset(direction)
                let beyond = point.offset(direction, by: 2)
                guard recorder.grid.contains(beyond), !recorder.grid.isOnBorder(wall),
                      recorder.grid[wall] == .wall, recorder.grid[beyond].isPassable
                else { continue }
                if recorder.grid.passableDegree(ofIndex: recorder.grid.index(of: beyond)) == 1 {
                    preferred.append(wall)
                } else {
                    fallback.append(wall)
                }
            }
            let choices = preferred.isEmpty ? fallback : preferred
            guard !choices.isEmpty else { continue }
            recorder.set(choices[random.uniform(below: choices.count)], to: .open)
        }
    }
}
