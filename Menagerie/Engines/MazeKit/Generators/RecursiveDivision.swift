extension PerfectMazeCarver {
    /// Recursive division, the one generator that *adds* walls.
    ///
    /// It splits each chamber with a wall along an even row or column, leaves
    /// a single gap at an odd position, and repeats inside both halves until
    /// every chamber is one room wide. Each split joins two trees through
    /// exactly one gap, so the result is still a perfect maze. Chambers are
    /// processed first-in, first-out, so the animation works from coarse to
    /// fine. The recorder must start from an open field.
    static func recursiveDivision(_ recorder: inout GenerationRecorder, random: inout MazeRandom) {
        let lattice = RoomLattice(width: recorder.grid.width, height: recorder.grid.height)
        guard lattice.count > 0 else { return }

        // Inclusive bounds; every bound sits on an odd (room) coordinate.
        struct Chamber {
            var minX, minY, maxX, maxY: Int
        }

        var queue = [Chamber(minX: 1, minY: 1, maxX: 2 * lattice.columns - 1, maxY: 2 * lattice.rows - 1)]
        var head = 0
        while head < queue.count {
            let chamber = queue[head]
            head += 1
            let roomsWide = (chamber.maxX - chamber.minX) / 2 + 1
            let roomsTall = (chamber.maxY - chamber.minY) / 2 + 1
            guard roomsWide > 1, roomsTall > 1 else { continue }

            // Cut across the longer dimension; break ties at random.
            let horizontal = roomsTall > roomsWide
                || (roomsTall == roomsWide && random.uniform(below: 2) == 0)
            if horizontal {
                let wallY = chamber.minY + 1 + 2 * random.uniform(below: roomsTall - 1)
                let gapX = chamber.minX + 2 * random.uniform(below: roomsWide)
                for x in chamber.minX...chamber.maxX where x != gapX {
                    recorder.set(MazePoint(x: x, y: wallY), to: .wall)
                }
                queue.append(Chamber(minX: chamber.minX, minY: chamber.minY, maxX: chamber.maxX, maxY: wallY - 1))
                queue.append(Chamber(minX: chamber.minX, minY: wallY + 1, maxX: chamber.maxX, maxY: chamber.maxY))
            } else {
                let wallX = chamber.minX + 1 + 2 * random.uniform(below: roomsWide - 1)
                let gapY = chamber.minY + 2 * random.uniform(below: roomsTall)
                for y in chamber.minY...chamber.maxY where y != gapY {
                    recorder.set(MazePoint(x: wallX, y: y), to: .wall)
                }
                queue.append(Chamber(minX: chamber.minX, minY: chamber.minY, maxX: wallX - 1, maxY: chamber.maxY))
                queue.append(Chamber(minX: wallX + 1, minY: chamber.minY, maxX: chamber.maxX, maxY: chamber.maxY))
            }
        }
    }
}
