import XCTest
@testable import MazeKit

final class MazeGeneratorTests: XCTestCase {
    private let perfectGenerators = MazeGenerator.allCases.filter(\.carvesPerfectMaze)
    private let sizes = [(3, 3), (5, 5), (7, 5), (5, 11), (21, 13), (31, 31), (48, 20)]
    private let seeds: [UInt64] = [0, 1, 42, 2_024, .max]

    // MARK: Perfect mazes

    func testPerfectGeneratorsCarveSpanningTrees() {
        for generator in perfectGenerators {
            for (width, height) in sizes {
                for seed in seeds {
                    let maze = generator.generate(width: width, height: height, seed: seed).maze
                    let topology = maze.topology
                    let context = "\(generator.name) \(width)×\(height) seed \(seed)"
                    XCTAssertEqual(topology.components, 1, "\(context): not connected")
                    XCTAssertEqual(topology.connections, topology.passableCells - 1, "\(context): not a tree")
                    XCTAssertTrue(topology.isPerfect, context)
                }
            }
        }
    }

    func testPerfectMazesHaveBlockStructure() {
        for generator in perfectGenerators {
            for seed in seeds {
                let maze = generator.generate(width: 25, height: 15, seed: seed).maze
                for y in 0..<maze.height {
                    for x in 0..<maze.width {
                        let cell = maze[x: x, y: y]
                        let isBorder = x == 0 || y == 0 || x == maze.width - 1 || y == maze.height - 1
                        if isBorder || (x.isMultiple(of: 2) && y.isMultiple(of: 2)) {
                            XCTAssertEqual(cell, .wall, "\(generator.name): border and pillars stay solid at (\(x), \(y))")
                        } else if !x.isMultiple(of: 2) && !y.isMultiple(of: 2) {
                            XCTAssertEqual(cell, .open, "\(generator.name): every room is carved at (\(x), \(y))")
                        }
                    }
                }
            }
        }
    }

    func testStartAndGoalAreReachableForEveryGenerator() {
        for generator in MazeGenerator.allCases {
            for seed in seeds {
                let maze = generator.generate(width: 33, height: 21, seed: seed, options: .init(braid: 0.3, mud: 0.2)).maze
                XCTAssertTrue(maze.isPassable(maze.start), generator.name)
                XCTAssertTrue(maze.isPassable(maze.goal), generator.name)
                XCTAssertTrue(maze.isReachable(maze.goal, from: maze.start), "\(generator.name) seed \(seed)")
            }
        }
    }

    func testEvenDimensionsRoundUpToOdd() {
        let maze = MazeGenerator.prim.generate(width: 10, height: 6, seed: 1).maze
        XCTAssertEqual(maze.width, 11)
        XCTAssertEqual(maze.height, 7)
        XCTAssertEqual(maze.goal, MazePoint(x: 9, y: 5))
    }

    /// Wilson's algorithm samples spanning trees uniformly. A 2 × 3 lattice
    /// of rooms has exactly 15 spanning trees, so each one should turn up
    /// about 1/15 of the time.
    func testWilsonSamplesSpanningTreesUniformly() {
        var counts: [[MazeCell]: Int] = [:]
        let samples = 6_000
        for seed in 0..<samples {
            let maze = MazeGenerator.wilson.generate(width: 5, height: 7, seed: UInt64(seed)).maze
            counts[maze.cells, default: 0] += 1
        }
        XCTAssertEqual(counts.count, 15)
        let expected = Double(samples) / 15
        for count in counts.values {
            // About five standard deviations either side of 400.
            XCTAssertEqual(Double(count), expected, accuracy: 100)
        }
    }

    // MARK: Replay

    func testReplayingStepsReproducesTheMaze() {
        for generator in MazeGenerator.allCases {
            let generation = generator.generate(width: 27, height: 17, seed: 8, options: .init(braid: 0.35, mud: 0.12))
            XCTAssertEqual(generation.grid(afterSteps: generation.steps.count), generation.maze, generator.name)
            XCTAssertEqual(generation.grid(afterSteps: 0), generation.initial, generator.name)
        }
    }

    func testStepsChangeTerrainAndBalanceMarks() {
        for generator in MazeGenerator.allCases {
            let generation = generator.generate(width: 27, height: 17, seed: 4, options: .init(braid: 0.5, mud: 0.1))
            var grid = generation.initial
            var marked = Set<MazePoint>()
            for step in generation.steps {
                switch step {
                case let .set(point, terrain):
                    XCTAssertNotEqual(grid[point], terrain, "\(generator.name): a set step must change the cell")
                    grid[point] = terrain
                case let .mark(point):
                    XCTAssertTrue(marked.insert(point).inserted, "\(generator.name): \(point) marked twice")
                case let .unmark(point):
                    XCTAssertNotNil(marked.remove(point), "\(generator.name): \(point) unmarked while not marked")
                }
            }
            XCTAssertTrue(marked.isEmpty, "\(generator.name): marks left behind")
        }
    }

    func testCarvingGeneratorsUseTheirWorkingSet() {
        for generator in [MazeGenerator.recursiveBacktracker, .prim, .wilson] {
            let generation = generator.generate(width: 21, height: 21, seed: 1)
            XCTAssertTrue(generation.steps.contains { if case .mark = $0 { return true } else { return false } }, generator.name)
        }
    }

    func testPhasesAreOrdered() {
        let generation = MazeGenerator.kruskal.generate(width: 21, height: 15, seed: 3, options: .init(braid: 0.5, mud: 0.2))
        XCTAssertLessThan(0, generation.mudStart)
        XCTAssertLessThan(generation.mudStart, generation.braidingStart)
        XCTAssertLessThan(generation.braidingStart, generation.steps.count)
        XCTAssertEqual(generation.phase(ofStep: 0), .carving)
        XCTAssertEqual(generation.phase(ofStep: generation.mudStart), .spreadingMud)
        XCTAssertEqual(generation.phase(ofStep: generation.braidingStart), .braiding)
        for index in generation.mudStart..<generation.braidingStart {
            XCTAssertEqual(generation.steps[index], .set(generation.steps[index].point, .mud))
        }
    }

    // MARK: Determinism

    func testSeededGenerationIsDeterministic() {
        let options = MazeGenerator.Options(braid: 0.25, mud: 0.1)
        for generator in MazeGenerator.allCases {
            let first = generator.generate(width: 31, height: 19, seed: 77, options: options)
            let second = generator.generate(width: 31, height: 19, seed: 77, options: options)
            XCTAssertEqual(first, second, generator.name)
            if generator != .empty {
                let other = generator.generate(width: 31, height: 19, seed: 78, options: options)
                XCTAssertNotEqual(first.maze, other.maze, "\(generator.name): different seeds should differ")
            }
        }
    }

    // MARK: Braiding and mud

    func testFullBraidRemovesEveryDeadEnd() {
        for generator in perfectGenerators {
            let perfect = generator.generate(width: 31, height: 21, seed: 12).maze
            let braided = generator.generate(width: 31, height: 21, seed: 12, options: .init(braid: 1)).maze
            XCTAssertGreaterThan(perfect.topology.deadEnds, 0)
            XCTAssertEqual(braided.topology.deadEnds, 0, generator.name)
            XCTAssertGreaterThan(braided.topology.loops, 0, generator.name)
            XCTAssertEqual(braided.topology.components, 1, generator.name)
        }
    }

    func testLargerBraidOpensASupersetOfWalls() {
        for generator in MazeGenerator.allCases {
            var previous = generator.generate(width: 29, height: 19, seed: 21).maze
            for braid in [0.1, 0.3, 0.6, 1.0] {
                let current = generator.generate(width: 29, height: 19, seed: 21, options: .init(braid: braid)).maze
                for index in current.cells.indices where previous.cells[index].isPassable {
                    XCTAssertTrue(current.cells[index].isPassable, "\(generator.name): braid \(braid) closed a passage")
                }
                XCTAssertGreaterThanOrEqual(current.topology.loops, previous.topology.loops)
                previous = current
            }
        }
    }

    func testMudLeavesWallsAndEndpointsAlone() {
        for generator in MazeGenerator.allCases {
            let dry = generator.generate(width: 31, height: 21, seed: 5, options: .init(braid: 0.4))
            let muddy = generator.generate(width: 31, height: 21, seed: 5, options: .init(braid: 0.4, mud: 0.2))
            let floor = dry.maze.count(of: .open) - 2
            let mud = muddy.maze.count(of: .mud)
            XCTAssertEqual(Double(mud), 0.2 * Double(floor), accuracy: 0.05 * Double(floor) + 2, generator.name)
            XCTAssertEqual(muddy.maze[muddy.maze.start], .open)
            XCTAssertEqual(muddy.maze[muddy.maze.goal], .open)
            for index in dry.maze.cells.indices {
                XCTAssertEqual(dry.maze.cells[index] == .wall, muddy.maze.cells[index] == .wall, "\(generator.name): mud moved a wall")
            }
        }
    }

    // MARK: Open fields

    func testEmptyFieldIsOpenFloor() {
        let generation = MazeGenerator.empty.generate(width: 15, height: 9, seed: 0)
        XCTAssertTrue(generation.steps.isEmpty)
        XCTAssertEqual(generation.maze, MazeGrid.openField(width: 15, height: 9))
    }

    func testObstaclesKeepEndpointsClear() {
        for seed in 0..<40 {
            let maze = MazeGenerator.obstacles.generate(width: 41, height: 27, seed: UInt64(seed)).maze
            let interior = 39 * 25
            let rubble = maze.count(of: .wall) - (2 * 41 + 2 * 25)
            XCTAssertEqual(Double(rubble), OpenFieldBuilder.obstacleDensity * Double(interior), accuracy: 2)
            for dx in -1...1 {
                for dy in -1...1 {
                    let nearStart = MazePoint(x: maze.start.x + dx, y: maze.start.y + dy)
                    let nearGoal = MazePoint(x: maze.goal.x + dx, y: maze.goal.y + dy)
                    if !maze.isOnBorder(nearStart) { XCTAssertTrue(maze.isPassable(nearStart)) }
                    if !maze.isOnBorder(nearGoal) { XCTAssertTrue(maze.isPassable(nearGoal)) }
                }
            }
            XCTAssertTrue(maze.isReachable(maze.goal, from: maze.start), "seed \(seed)")
        }
    }
}
