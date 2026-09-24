/// Generators that start from an open field rather than carving rooms.
enum OpenFieldBuilder {
    /// The fraction of the interior that becomes rubble.
    static let obstacleDensity = 0.27

    /// Rubble scattered over an open field, in short random strokes of one to
    /// three cells. The cells around the start and goal stay clear. If a
    /// layout cuts the goal off, the next layout from the same random stream
    /// is tried, so the result stays deterministic.
    static func obstacles(width: Int, height: Int, random: inout MazeRandom) -> GenerationRecorder {
        let field = MazeGrid.openField(width: width, height: height)
        let attempts = 16
        var recorder = GenerationRecorder(field)
        for _ in 0..<attempts {
            recorder = GenerationRecorder(field)
            scatter(&recorder, random: &random)
            if recorder.grid.isReachable(recorder.grid.goal, from: recorder.grid.start) { break }
        }
        return recorder
    }

    private static func scatter(_ recorder: inout GenerationRecorder, random: inout MazeRandom) {
        let grid = recorder.grid
        let interiorWidth = grid.width - 2
        let interiorHeight = grid.height - 2
        let target = Int(Double(interiorWidth * interiorHeight) * obstacleDensity)
        let directions = MazeDirection.allCases

        func isKeptClear(_ point: MazePoint) -> Bool {
            max(abs(point.x - grid.start.x), abs(point.y - grid.start.y)) <= 1
                || max(abs(point.x - grid.goal.x), abs(point.y - grid.goal.y)) <= 1
        }

        var placed = 0
        var strokes = 0
        while placed < target && strokes < 4 * interiorWidth * interiorHeight {
            strokes += 1
            let origin = MazePoint(x: 1 + random.uniform(below: interiorWidth), y: 1 + random.uniform(below: interiorHeight))
            let direction = directions[random.uniform(below: directions.count)]
            let length = 1 + random.uniform(below: 3)
            for distance in 0..<length where placed < target {
                let point = origin.offset(direction, by: distance)
                guard grid.contains(point), !grid.isOnBorder(point), !isKeptClear(point),
                      recorder.grid[point] == .open
                else { continue }
                recorder.set(point, to: .wall)
                placed += 1
            }
        }
    }
}
