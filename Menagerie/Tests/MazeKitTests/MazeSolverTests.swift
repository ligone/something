import XCTest
@testable import MazeKit

final class MazeSolverTests: XCTestCase {
    // MARK: Validity

    func testEveryPathIsContiguousAndAvoidsWalls() {
        for grid in Reference.mixedGrids + Reference.uniformGrids {
            for trace in MazeSolver.solveAll(grid) {
                XCTAssertTrue(trace.stats.foundGoal, "\(trace.solver.name) failed on a solvable maze")
                assertValidPath(trace, in: grid)
            }
        }
    }

    func testEventsAgreeWithStats() {
        for grid in Reference.mixedGrids {
            for trace in MazeSolver.solveAll(grid) {
                let expansions = trace.events.filter { $0.kind == .expanded }
                let discoveries = trace.events.filter { $0.kind == .discovered }
                XCTAssertEqual(expansions.count, trace.stats.nodesExpanded, trace.solver.name)
                XCTAssertEqual(discoveries.count, trace.stats.nodesDiscovered, trace.solver.name)
                XCTAssertEqual(Set(expansions.map(\.point)).count, expansions.count, "\(trace.solver.name) expanded a cell twice")
                XCTAssertEqual(Set(discoveries.map(\.point)).count, discoveries.count, "\(trace.solver.name) discovered a cell twice")

                var discovered = Set<MazePoint>()
                for event in trace.events {
                    XCTAssertTrue(grid.isPassable(event.point), "\(trace.solver.name) touched a wall")
                    if event.kind == .discovered {
                        discovered.insert(event.point)
                    } else {
                        XCTAssertTrue(discovered.contains(event.point), "\(trace.solver.name) expanded an undiscovered cell")
                    }
                }
            }
        }
    }

    // MARK: Optimality

    func testBreadthFirstMatchesDijkstraOnUniformGrid() {
        for grid in Reference.uniformGrids {
            let bfs = MazeSolver.breadthFirst.solve(grid)
            let dijkstra = MazeSolver.dijkstra.solve(grid)
            XCTAssertEqual(bfs.stats.pathLength, dijkstra.stats.pathLength)
            XCTAssertEqual(dijkstra.stats.pathLength, dijkstra.stats.pathCost, "Every step costs 1 without mud")
            XCTAssertEqual(bfs.stats.pathLength, Reference.fewestMoves(grid))
        }
    }

    func testDijkstraFindsTheCheapestPath() {
        for grid in Reference.mixedGrids {
            XCTAssertEqual(MazeSolver.dijkstra.solve(grid).stats.pathCost, Reference.cheapestCost(grid))
        }
    }

    func testAStarCostMatchesDijkstraWithMud() {
        var mudMattered = false
        for grid in Reference.mixedGrids {
            let dijkstra = MazeSolver.dijkstra.solve(grid)
            let aStar = MazeSolver.aStar.solve(grid)
            let bfs = MazeSolver.breadthFirst.solve(grid)
            XCTAssertEqual(aStar.stats.pathCost, dijkstra.stats.pathCost)
            XCTAssertLessThanOrEqual(aStar.stats.nodesExpanded, dijkstra.stats.nodesExpanded, "A* never expands more than Dijkstra")
            if bfs.stats.pathCost > dijkstra.stats.pathCost { mudMattered = true }
        }
        XCTAssertTrue(mudMattered, "The fixtures should include mazes where mud changes the best route")
    }

    func testBidirectionalMatchesBreadthFirstLength() {
        for grid in Reference.mixedGrids + Reference.uniformGrids {
            let bfs = MazeSolver.breadthFirst.solve(grid)
            let bidirectional = MazeSolver.bidirectional.solve(grid)
            XCTAssertEqual(bidirectional.stats.pathLength, bfs.stats.pathLength)
        }
    }

    func testNoSolverBeatsTheOptimalOnes() {
        for grid in Reference.mixedGrids {
            let fewest = MazeSolver.breadthFirst.solve(grid).stats.pathLength
            let cheapest = MazeSolver.dijkstra.solve(grid).stats.pathCost
            for trace in MazeSolver.solveAll(grid) {
                XCTAssertGreaterThanOrEqual(trace.stats.pathLength, fewest, trace.solver.name)
                XCTAssertGreaterThanOrEqual(trace.stats.pathCost, cheapest, trace.solver.name)
            }
        }
    }

    func testDepthFirstAndGreedyCanBeSuboptimal() {
        var longerDepthFirst = false
        var longerGreedy = false
        for grid in Reference.mixedGrids {
            let fewest = MazeSolver.breadthFirst.solve(grid).stats.pathLength
            longerDepthFirst = longerDepthFirst || MazeSolver.depthFirst.solve(grid).stats.pathLength > fewest
            longerGreedy = longerGreedy || MazeSolver.greedyBestFirst.solve(grid).stats.pathLength > fewest
        }
        XCTAssertTrue(longerDepthFirst)
        XCTAssertTrue(longerGreedy)
    }

    func testDepthFirstSweepsAnOpenFieldRowByRow() {
        // An odd number of rows makes the sweep end exactly on the goal, so
        // the path threads every interior cell.
        let field = MazeGrid.openField(width: 11, height: 9)
        let trace = MazeSolver.depthFirst.solve(field)
        XCTAssertEqual(trace.stats.pathLength, 9 * 7 - 1)
        XCTAssertEqual(Array(trace.path.prefix(10)), (1...9).map { MazePoint(x: $0, y: 1) } + [MazePoint(x: 9, y: 2)])
        assertValidPath(trace, in: field)
    }

    func testWeightedSearchesDetourAroundMud() throws {
        let grid = try XCTUnwrap(MazeGrid(ascii: [
            "#########",
            "#S~~~~~G#",
            "#.#####.#",
            "#.......#",
            "#########",
        ]))
        let bfs = MazeSolver.breadthFirst.solve(grid)
        XCTAssertEqual(bfs.stats.pathLength, 6)
        XCTAssertEqual(bfs.stats.pathCost, 5 * 5 + 1)
        for solver in [MazeSolver.dijkstra, .aStar] {
            let trace = solver.solve(grid)
            XCTAssertEqual(trace.stats.pathLength, 10, solver.name)
            XCTAssertEqual(trace.stats.pathCost, 10, solver.name)
            XCTAssertFalse(trace.path.contains { grid[$0] == .mud }, solver.name)
        }
    }

    // MARK: Edge cases

    func testUnreachableGoalIsReported() throws {
        let grid = try XCTUnwrap(MazeGrid(ascii: [
            "#######",
            "#S..#G#",
            "#...###",
            "#######",
        ]))
        for trace in MazeSolver.solveAll(grid) {
            XCTAssertFalse(trace.stats.foundGoal, trace.solver.name)
            XCTAssertTrue(trace.path.isEmpty, trace.solver.name)
            XCTAssertEqual(trace.stats.pathLength, 0, trace.solver.name)
            XCTAssertEqual(trace.stats.pathCost, 0, trace.solver.name)
            if trace.solver != .bidirectional {
                XCTAssertEqual(trace.stats.nodesExpanded, 6, "\(trace.solver.name) should exhaust the start's region")
            }
        }
    }

    func testWalledInEndpointsAreUnsolvable() {
        var grid = MazeGrid.openField(width: 7, height: 7)
        grid[grid.goal] = .wall
        for trace in MazeSolver.solveAll(grid) {
            XCTAssertFalse(trace.stats.foundGoal)
            XCTAssertTrue(trace.events.isEmpty)
        }
        grid = MazeGrid.openField(width: 7, height: 7)
        grid.start = MazePoint(x: 0, y: 0)
        XCTAssertFalse(MazeSolver.aStar.solve(grid).stats.foundGoal)
    }

    func testStartEqualToGoal() {
        var grid = MazeGrid.openField(width: 7, height: 5)
        grid.goal = grid.start
        for trace in MazeSolver.solveAll(grid) {
            XCTAssertTrue(trace.stats.foundGoal, trace.solver.name)
            XCTAssertEqual(trace.path, [grid.start], trace.solver.name)
            XCTAssertEqual(trace.stats.pathLength, 0, trace.solver.name)
            XCTAssertEqual(trace.stats.pathCost, 0, trace.solver.name)
            XCTAssertEqual(trace.stats.nodesExpanded, 1, trace.solver.name)
        }
    }

    func testAdjacentEndpoints() {
        var grid = MazeGrid.openField(width: 7, height: 5)
        grid.goal = MazePoint(x: 2, y: 1)
        for trace in MazeSolver.solveAll(grid) {
            XCTAssertEqual(trace.path, [grid.start, grid.goal], trace.solver.name)
        }
    }

    func testSolversAreDeterministic() {
        let grid = Reference.mixedGrids[4]
        for solver in MazeSolver.allCases {
            XCTAssertEqual(solver.solve(grid), solver.solve(grid), solver.name)
        }
    }

    // MARK: Timeline

    func testTimelineIndexesTheTrace() {
        for grid in Reference.mixedGrids.prefix(6) {
            for trace in MazeSolver.solveAll(grid) {
                let timeline = SearchTimeline(trace: trace, grid: grid)
                XCTAssertEqual(timeline.stepCount, trace.stats.nodesExpanded)
                XCTAssertEqual(timeline.discoveryOrder.count, trace.stats.nodesDiscovered)
                XCTAssertEqual(timeline.discoveryStep, timeline.discoveryStep.sorted(), "Discovery steps never decrease")
                XCTAssertEqual(timeline.discoveryCount(atStep: timeline.stepCount), timeline.discoveryOrder.count)

                let startIndex = grid.index(of: grid.start)
                let goalIndex = grid.index(of: grid.goal)
                let initialFrontier = timeline.frontier(atStep: 0)
                if trace.solver == .bidirectional {
                    XCTAssertEqual(initialFrontier, [startIndex, goalIndex])
                } else {
                    XCTAssertEqual(initialFrontier, [startIndex])
                    XCTAssertEqual(Int(timeline.expansionStep[goalIndex]), timeline.stepCount, "The goal is expanded last")
                }
                for (offset, cell) in timeline.expansionOrder.enumerated() {
                    XCTAssertEqual(Int(timeline.expansionStep[Int(cell)]), offset + 1)
                    XCTAssertFalse(timeline.isExpanded(Int(cell), atStep: offset))
                    XCTAssertTrue(timeline.isExpanded(Int(cell), atStep: offset + 1))
                }
                XCTAssertEqual(timeline.expansionFromGoal.contains(true), trace.solver == .bidirectional)
            }
        }
    }
}
