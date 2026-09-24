import XCTest
@testable import MazeKit

final class MazeGridTests: XCTestCase {
    func testNewGridIsSolidWithCornerEndpoints() {
        let grid = MazeGrid(width: 7, height: 5)
        XCTAssertEqual(grid.cellCount, 35)
        XCTAssertEqual(grid.count(of: .wall), 35)
        XCTAssertEqual(grid.start, MazePoint(x: 1, y: 1))
        XCTAssertEqual(grid.goal, MazePoint(x: 5, y: 3))
    }

    func testIndexAndPointRoundTrip() {
        let grid = MazeGrid(width: 9, height: 7)
        for index in 0..<grid.cellCount {
            XCTAssertEqual(grid.index(of: grid.point(at: index)), index)
        }
        XCTAssertEqual(grid.point(at: 10), MazePoint(x: 1, y: 1))
    }

    func testOutsideReadsAsWallAndBorderIsDetected() {
        let grid = MazeGrid.openField(width: 5, height: 5)
        XCTAssertEqual(grid[MazePoint(x: -1, y: 2)], .wall)
        XCTAssertEqual(grid[x: 5, y: 0], .wall)
        XCTAssertFalse(grid.isPassable(MazePoint(x: 2, y: 9)))
        XCTAssertTrue(grid.isOnBorder(MazePoint(x: 0, y: 3)))
        XCTAssertTrue(grid.isOnBorder(MazePoint(x: 4, y: 4)))
        XCTAssertFalse(grid.isOnBorder(MazePoint(x: 2, y: 2)))
        XCTAssertFalse(grid.isOnBorder(MazePoint(x: 5, y: 2)), "Outside points are not on the border")
    }

    func testAsciiRoundTrip() throws {
        let picture = [
            "#######",
            "#S.~..#",
            "#.#.#.#",
            "#..~.G#",
            "#######",
        ]
        let grid = try XCTUnwrap(MazeGrid(ascii: picture))
        XCTAssertEqual(grid.width, 7)
        XCTAssertEqual(grid.height, 5)
        XCTAssertEqual(grid.start, MazePoint(x: 1, y: 1))
        XCTAssertEqual(grid.goal, MazePoint(x: 5, y: 3))
        XCTAssertEqual(grid[x: 3, y: 1], .mud)
        XCTAssertEqual(grid.count(of: .mud), 2)
        XCTAssertEqual(grid.asciiRows, picture)
    }

    func testAsciiRejectsMalformedPictures() {
        XCTAssertNil(MazeGrid(ascii: ["###", "#.#"]), "Too few rows")
        XCTAssertNil(MazeGrid(ascii: ["####", "#.#", "####"]), "Ragged rows")
        XCTAssertNil(MazeGrid(ascii: ["###", "#x#", "###"]), "Unknown character")
    }

    func testTerrainCosts() {
        XCTAssertNil(MazeCell.wall.stepCost)
        XCTAssertEqual(MazeCell.open.stepCost, 1)
        XCTAssertEqual(MazeCell.mud.stepCost, 5)
        XCTAssertFalse(MazeCell.wall.isPassable)
        XCTAssertTrue(MazeCell.mud.isPassable)
    }

    func testPassableNeighborsFollowFixedOrder() throws {
        let grid = try XCTUnwrap(MazeGrid(ascii: [
            "#####",
            "#...#",
            "#.S.#",
            "#.#.#",
            "#####",
        ]))
        // East, north, west; south is a wall.
        XCTAssertEqual(grid.passableNeighbors(of: grid.start), [
            MazePoint(x: 3, y: 2), MazePoint(x: 2, y: 1), MazePoint(x: 1, y: 2),
        ])
    }

    func testApplyReplaysOnlySetSteps() {
        var grid = MazeGrid(width: 5, height: 5)
        grid.apply(.mark(MazePoint(x: 1, y: 1)))
        XCTAssertEqual(grid[x: 1, y: 1], .wall)
        grid.apply(.set(MazePoint(x: 1, y: 1), .mud))
        XCTAssertEqual(grid[x: 1, y: 1], .mud)
    }

    // MARK: Topology

    func testTopologyOfSingleLoop() throws {
        let grid = try XCTUnwrap(MazeGrid(ascii: [
            "#####",
            "#S..#",
            "#.#.#",
            "#..G#",
            "#####",
        ]))
        let topology = grid.topology
        XCTAssertEqual(topology.passableCells, 8)
        XCTAssertEqual(topology.connections, 8)
        XCTAssertEqual(topology.components, 1)
        XCTAssertEqual(topology.loops, 1)
        XCTAssertEqual(topology.deadEnds, 0)
        XCTAssertFalse(topology.isPerfect)
    }

    func testTopologyOfSeparateCorridors() throws {
        let grid = try XCTUnwrap(MazeGrid(ascii: [
            "#######",
            "#S.#..#",
            "###.#.#",
            "#..G#.#",
            "#######",
        ]))
        let topology = grid.topology
        XCTAssertEqual(topology.passableCells, 10)
        XCTAssertEqual(topology.components, 3)
        XCTAssertEqual(topology.loops, 0)
        XCTAssertEqual(topology.deadEnds, 6)
        XCTAssertFalse(topology.isPerfect, "A forest of several trees is not a perfect maze")
    }

    func testOpenFieldTopology() {
        let grid = MazeGrid.openField(width: 12, height: 9)
        let topology = grid.topology
        let columns = 10
        let rows = 7
        XCTAssertEqual(topology.passableCells, columns * rows)
        XCTAssertEqual(topology.components, 1)
        XCTAssertEqual(topology.deadEnds, 0)
        // A w × h lattice of cells encloses (w − 1)(h − 1) unit squares, each an independent loop.
        XCTAssertEqual(topology.loops, (columns - 1) * (rows - 1))
    }

    func testReachability() throws {
        let grid = try XCTUnwrap(MazeGrid(ascii: [
            "#######",
            "#S.#..#",
            "#..#.G#",
            "#######",
        ]))
        XCTAssertFalse(grid.isReachable(grid.goal, from: grid.start))
        XCTAssertTrue(grid.isReachable(MazePoint(x: 2, y: 2), from: grid.start))
        XCTAssertFalse(grid.isReachable(MazePoint(x: 3, y: 1), from: grid.start), "Walls are never reachable")
        let reached = grid.reachableCells(from: grid.start)
        XCTAssertEqual(reached.filter { $0 }.count, 4)
        XCTAssertEqual(grid.reachableCells(from: MazePoint(x: 0, y: 0)).filter { $0 }.count, 0)
    }
}
