import XCTest
@testable import MazeKit

/// Independent reference answers and shared fixtures for the MazeKit test suite.
enum Reference {
    /// The cheapest path cost from start to goal, found by Bellman–Ford-style
    /// relaxation until nothing changes. It is slow but obviously correct, and
    /// it shares no code with the solvers under test.
    static func cheapestCost(_ grid: MazeGrid) -> Int? {
        guard grid.isPassable(grid.start), grid.isPassable(grid.goal) else { return nil }
        var best = [MazePoint: Int]()
        best[grid.start] = 0
        var changed = true
        while changed {
            changed = false
            for y in 0..<grid.height {
                for x in 0..<grid.width {
                    let point = MazePoint(x: x, y: y)
                    guard let cost = best[point] else { continue }
                    for next in grid.passableNeighbors(of: point) {
                        let candidate = cost + (grid[next].stepCost ?? 0)
                        if candidate < best[next, default: .max] {
                            best[next] = candidate
                            changed = true
                        }
                    }
                }
            }
        }
        return best[grid.goal]
    }

    /// The fewest moves from start to goal, by a plain flood fill over points.
    static func fewestMoves(_ grid: MazeGrid) -> Int? {
        guard grid.isPassable(grid.start), grid.isPassable(grid.goal) else { return nil }
        var distance = [grid.start: 0]
        var queue = [grid.start]
        var head = 0
        while head < queue.count {
            let point = queue[head]
            head += 1
            for next in grid.passableNeighbors(of: point) where distance[next] == nil {
                distance[next] = distance[point]! + 1
                queue.append(next)
            }
        }
        return distance[grid.goal]
    }

    /// A varied collection of mazes: every generator, several seeds, with
    /// loops and mud so that routes differ in both length and cost.
    static let mixedGrids: [MazeGrid] = MazeGenerator.allCases.flatMap { generator in
        [3, 17, 99].map { seed in
            generator.generate(width: 31, height: 21, seed: UInt64(seed), options: .init(braid: 0.4, mud: 0.15)).maze
        }
    }

    /// The same mazes with loops but no mud, so every step costs 1.
    static let uniformGrids: [MazeGrid] = MazeGenerator.allCases.flatMap { generator in
        [5, 23].map { seed in
            generator.generate(width: 29, height: 19, seed: UInt64(seed), options: .init(braid: 0.5)).maze
        }
    }
}

/// Asserts that a trace's path is a valid route. It must run from start to
/// goal in single orthogonal steps, over passable cells, without revisiting
/// a cell, and it must agree with the trace's statistics.
func assertValidPath(_ trace: SearchTrace, in grid: MazeGrid, file: StaticString = #filePath, line: UInt = #line) {
    let label = "\(trace.solver.name)"
    guard trace.stats.foundGoal else {
        XCTAssertTrue(trace.path.isEmpty, "\(label): unsolved trace has a path", file: file, line: line)
        return
    }
    XCTAssertEqual(trace.path.first, grid.start, "\(label): path must begin at the start", file: file, line: line)
    XCTAssertEqual(trace.path.last, grid.goal, "\(label): path must end at the goal", file: file, line: line)
    XCTAssertEqual(Set(trace.path).count, trace.path.count, "\(label): path revisits a cell", file: file, line: line)
    for point in trace.path {
        XCTAssertTrue(grid.isPassable(point), "\(label): path crosses a wall at \(point)", file: file, line: line)
    }
    for (a, b) in zip(trace.path, trace.path.dropFirst()) {
        XCTAssertTrue(a.isAdjacent(to: b), "\(label): path jumps from \(a) to \(b)", file: file, line: line)
    }
    let cost = trace.path.dropFirst().reduce(0) { $0 + (grid[$1].stepCost ?? 0) }
    XCTAssertEqual(trace.stats.pathLength, trace.path.count - 1, "\(label): wrong path length", file: file, line: line)
    XCTAssertEqual(trace.stats.pathCost, cost, "\(label): wrong path cost", file: file, line: line)
}
