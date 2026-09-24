import Foundation
import MazeKit
import Observation

/// The state behind Maze Lab: the maze, the playback of carving and searching,
/// painting, and the solver comparison.
///
/// The stage's `TimelineView` drives playback by calling ``tick(at:)`` once per
/// frame. Generating and solving take well under a millisecond at these sizes,
/// so all of it runs synchronously on the main actor. No timers or tasks need
/// cancelling.
@MainActor
@Observable
final class MazeLabModel {
    enum Activity: Equatable {
        case idle
        case generating
        case searching
    }

    // MARK: Settings

    /// Choosing a generator carves a fresh maze with it, animated.
    var generator: MazeGenerator {
        get { storedGenerator }
        set {
            guard newValue != storedGenerator else { return }
            storedGenerator = newValue
            generate()
        }
    }

    /// Changing the size carves a fresh maze.
    var size: MazeSize {
        get { storedSize }
        set {
            guard newValue != storedSize else { return }
            storedSize = newValue
            generate()
        }
    }

    /// The fraction of dead ends knocked through. Changing it re-braids the current maze live.
    var loops: Double {
        get { storedLoops }
        set {
            guard newValue != storedLoops else { return }
            storedLoops = newValue
            refinish()
        }
    }

    /// Whether mazes get mud patches. Toggling it updates the current maze live.
    var mudEnabled: Bool {
        get { storedMud }
        set {
            guard newValue != storedMud else { return }
            storedMud = newValue
            refinish()
        }
    }

    /// Choosing a solver runs it, animated.
    var solver: MazeSolver {
        get { storedSolver }
        set {
            guard newValue != storedSolver else { return }
            storedSolver = newValue
            solve()
        }
    }

    /// The speed slider, from 0 to 1. See ``MazePlaybackSpeed``.
    var speed = MazePlaybackSpeed.defaultSlider

    var tool: MazeTool = .wall

    /// The cell under the pointer, for the brush preview.
    var hoverCell: MazePoint?

    private var storedGenerator: MazeGenerator = .recursiveBacktracker
    private var storedSize: MazeSize = .medium
    private var storedLoops = 0.2
    private var storedMud = true
    private var storedSolver: MazeSolver = .aStar

    // MARK: Maze state

    /// The board's size in cells. It changes only when a new maze is carved,
    /// so views that depend only on the board's size skip playback frames.
    private(set) var columns: Int
    private(set) var rows: Int
    /// The current maze, including the user's paint. While a new maze is
    /// being carved it still holds the previous one.
    private(set) var grid: MazeGrid
    /// The structure of the current maze, or `nil` while a new one is carved.
    private(set) var topology: MazeTopology?
    /// The carving on show, if any.
    private(set) var carving: MazeCarvingPlayback?
    /// The latest search. It stays on show when it finishes.
    private(set) var search: MazeSearchPlayback?
    private(set) var activity: Activity = .idle
    private(set) var isPaused = false
    /// Every solver's results on the current maze, while the comparison is open.
    private(set) var comparison: [MazeComparisonRow]?
    /// When the solved path began to draw itself in.
    private(set) var pathRevealStart = Date.distantPast

    /// The grid to draw: the carving in progress, or else the current maze.
    var displayGrid: MazeGrid { carving?.grid ?? grid }

    // MARK: Private state

    /// Everything needed to carve the current maze again with different finishing options.
    private struct Recipe {
        let generator: MazeGenerator
        let width: Int
        let height: Int
        let seed: UInt64
    }

    private enum Stroke {
        case paint(MazeCell, last: MazePoint)
        case move(MazeEndpoint)
        case ignored
    }

    @ObservationIgnored private var recipe: Recipe?
    /// The user's edits, re-applied whenever the maze is re-braided.
    @ObservationIgnored private var paintedCells: [Int: MazeCell] = [:]
    @ObservationIgnored private var movedStart: MazePoint?
    @ObservationIgnored private var movedGoal: MazePoint?
    @ObservationIgnored private var stroke: Stroke?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var boardAspect = 1.35
    @ObservationIgnored private var hasBoardArea = false
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var hasBegun = false
    @ObservationIgnored private var isCaptureTour = false

    /// A fixed seed for CI screenshots, so every capture shows the same maze.
    private static let captureSeed: UInt64 = 0x4D41_5A45

    init() {
        let size = MazeSize.medium.dimensions(aspectRatio: 1.35)
        columns = size.width
        rows = size.height
        grid = MazeGrid(width: size.width, height: size.height)
    }

    // MARK: Lifecycle

    /// Call when the exhibit appears. The opening show starts as soon as the
    /// stage has been measured.
    func begin(captureTour: Bool) {
        isVisible = true
        isCaptureTour = captureTour
        isPaused = false
        lastTick = nil
        startIfReady()
    }

    /// Call when the exhibit disappears. It drops any half-finished gesture
    /// and pauses playback.
    func end() {
        isVisible = false
        stroke = nil
        hoverCell = nil
        lastTick = nil
        if activity != .idle { isPaused = true }
    }

    /// Records the area the board may fill. New mazes take its aspect ratio.
    func setBoardArea(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        boardAspect = Double(size.width / size.height)
        hasBoardArea = true
        startIfReady()
    }

    /// The opening show: a maze carved by the recursive backtracker, then A*.
    /// For CI screenshots, it jumps straight to a solved maze with the comparison open.
    private func startIfReady() {
        guard isVisible, hasBoardArea, !hasBegun else { return }
        hasBegun = true
        if isCaptureTour {
            carve(seed: Self.captureSeed, animated: false)
            compareAll()
        } else {
            generate()
        }
    }

    // MARK: Playback

    /// Search steps per second at the current speed and maze size.
    var searchStepsPerSecond: Double {
        let sizeFactor = Double(columns * rows) / MazePlaybackSpeed.referenceCells
        return MazePlaybackSpeed.stepsPerSecond(slider: speed) * sizeFactor
    }

    /// Carving steps per second at the current speed and maze size.
    var carvingStepsPerSecond: Double {
        searchStepsPerSecond * MazePlaybackSpeed.carvingBoost
    }

    /// Whether something is playing and not paused.
    var isAnimating: Bool { activity != .idle && !isPaused }

    /// The stage hint for what a click does right now.
    var hint: String {
        switch activity {
        case .generating, .searching: "Click the maze to finish instantly"
        case .idle: tool.stageHint
        }
    }

    /// The solved route once the search has finished, or empty.
    var visibleRoute: [MazePoint] {
        guard let search, search.isFinished else { return [] }
        return search.trace.path
    }

    /// How much of the route is drawn at `date`, from 0 to 1. It eases out
    /// as it reaches the goal, and longer routes take a little longer.
    func routeReveal(at date: Date) -> Double {
        let duration = min(0.35 + 0.004 * Double(visibleRoute.count), 1.1)
        let progress = min(max(date.timeIntervalSince(pathRevealStart) / duration, 0), 1)
        return 1 - pow(1 - progress, 3)
    }

    /// Advances playback to `date`. The stage calls this once per display frame.
    func tick(at date: Date) {
        defer { lastTick = date }
        guard isAnimating, let lastTick else { return }
        // Clamp the step so a stalled frame slows the show instead of skipping it.
        let elapsed = min(max(date.timeIntervalSince(lastTick), 0), 1.0 / 20.0)
        switch activity {
        case .generating:
            carving?.advance(by: elapsed * carvingStepsPerSecond)
            if carving?.isFinished ?? true {
                finishCarving(animatingSearch: true)
            }
        case .searching:
            search?.advance(by: elapsed * searchStepsPerSecond)
            if search?.isFinished ?? true {
                activity = .idle
                pathRevealStart = date
            }
        case .idle:
            break
        }
    }

    func togglePause() {
        guard activity != .idle else { return }
        isPaused.toggle()
        lastTick = nil
    }

    /// Finishes whatever is playing: carving and search both complete at once.
    func skipAhead() {
        switch activity {
        case .generating:
            finishCarving(animatingSearch: false)
            pathRevealStart = Date()
        case .searching:
            search?.finish()
            activity = .idle
            isPaused = false
            pathRevealStart = Date()
        case .idle:
            break
        }
    }

    // MARK: Generating

    private var finishingOptions: MazeGenerator.Options {
        MazeGenerator.Options(braid: storedLoops, mud: storedMud ? 0.12 : 0)
    }

    /// Carves a fresh maze from a new random seed with the current generator,
    /// animated, then solves it.
    func generate() {
        carve(seed: UInt64.random(in: .min ... .max), animated: true)
    }

    private func carve(seed: UInt64, animated: Bool) {
        let dimensions = storedSize.dimensions(aspectRatio: boardAspect)
        let recipe = Recipe(generator: storedGenerator, width: dimensions.width, height: dimensions.height, seed: seed)
        self.recipe = recipe
        columns = recipe.width
        rows = recipe.height
        paintedCells = [:]
        movedStart = nil
        movedGoal = nil
        let result = recipe.generator.generate(
            width: recipe.width, height: recipe.height, seed: recipe.seed, options: finishingOptions
        )
        search = nil
        if animated {
            topology = nil
            carving = MazeCarvingPlayback(result)
            activity = .generating
            isPaused = false
            lastTick = nil
        } else {
            carving = nil
            commit(result.maze)
            solve(animated: false)
        }
    }

    private func finishCarving(animatingSearch: Bool) {
        guard let playback = carving else { return }
        carving = nil
        activity = .idle
        isPaused = false
        commit(playback.generation.maze)
        solve(animated: animatingSearch)
    }

    /// Re-carves the current maze from its seed with the latest loop and mud
    /// settings, then re-applies the user's paint and moved endpoints.
    private func refinish() {
        guard let recipe else { return }
        if carving != nil { finishCarving(animatingSearch: false) }
        var maze = recipe.generator.generate(
            width: recipe.width, height: recipe.height, seed: recipe.seed, options: finishingOptions
        ).maze
        for (index, terrain) in paintedCells {
            maze[maze.point(at: index)] = terrain
        }
        if let movedStart { maze.start = movedStart }
        if let movedGoal { maze.goal = movedGoal }
        // An endpoint may sit on a wall cell that fewer loops no longer opens.
        for endpoint in [maze.start, maze.goal] where !maze.isPassable(endpoint) {
            maze[endpoint] = .open
        }
        commit(maze)
        resolveInstantly()
    }

    private func commit(_ maze: MazeGrid) {
        grid = maze
        topology = maze.topology
        refreshComparison()
    }

    // MARK: Solving

    /// Runs the selected solver on the current maze, animated.
    func solve() {
        solve(animated: true)
    }

    private func solve(animated: Bool) {
        // During carving, the solver runs as soon as the maze is finished.
        guard carving == nil else { return }
        search = MazeSearchPlayback(trace: storedSolver.solve(grid), grid: grid, finished: !animated)
        if animated {
            activity = .searching
            isPaused = false
            lastTick = nil
        } else {
            activity = .idle
            pathRevealStart = .distantPast
        }
    }

    /// Re-runs the latest search to completion straight away, so edits update the route live.
    private func resolveInstantly() {
        guard search != nil else { return }
        solve(animated: false)
    }

    // MARK: Comparing

    /// Runs every solver on the current maze. The results stay live, following
    /// every new maze and edit, until hidden.
    func compareAll() {
        if carving != nil { finishCarving(animatingSearch: false) }
        comparison = MazeSolver.solveAll(grid).map(MazeComparisonRow.init)
    }

    func hideComparison() {
        comparison = nil
    }

    private func refreshComparison() {
        guard comparison != nil else { return }
        comparison = MazeSolver.solveAll(grid).map(MazeComparisonRow.init)
    }

    // MARK: Painting

    /// A press or drag moved to a cell, or off the board when `cell` is `nil`.
    /// The first call of a gesture decides what the whole stroke does.
    func pointerMoved(to cell: MazePoint?) {
        guard let stroke else {
            beginStroke(at: cell)
            return
        }
        guard let cell else { return }
        switch stroke {
        case let .paint(terrain, last):
            self.stroke = .paint(terrain, last: cell)
            if paintLine(from: last, to: cell, with: terrain) { gridDidChange() }
        case let .move(endpoint):
            if move(endpoint, to: cell, clearingWalls: false) { gridDidChange() }
        case .ignored:
            break
        }
    }

    /// The press or drag ended.
    func pointerReleased() {
        stroke = nil
    }

    private func beginStroke(at cell: MazePoint?) {
        // A click during playback skips to the end instead of painting.
        guard activity == .idle else {
            skipAhead()
            stroke = .ignored
            return
        }
        guard let cell, grid.contains(cell) else {
            stroke = .ignored
            return
        }
        if cell == grid.start {
            stroke = .move(.start)
        } else if cell == grid.goal {
            stroke = .move(.goal)
        } else {
            switch tool {
            case .start, .goal:
                let endpoint: MazeEndpoint = tool == .start ? .start : .goal
                stroke = .move(endpoint)
                if move(endpoint, to: cell, clearingWalls: true) { gridDidChange() }
            case .wall, .mud, .erase:
                let terrain = terrain(for: tool, strokeStartingOn: grid[cell])
                stroke = .paint(terrain, last: cell)
                if paintLine(from: cell, to: cell, with: terrain) { gridDidChange() }
            }
        }
    }

    /// The Wall and Mud tools toggle. A stroke that begins on the tool's own
    /// terrain clears it instead.
    private func terrain(for tool: MazeTool, strokeStartingOn existing: MazeCell) -> MazeCell {
        switch tool {
        case .wall: existing == .wall ? .open : .wall
        case .mud: existing == .mud ? .open : .mud
        case .erase, .start, .goal: .open
        }
    }

    /// Paints every cell on a four-connected line, so a fast drag leaves no
    /// gaps and painted walls stay watertight. Returns whether anything changed.
    private func paintLine(from start: MazePoint, to end: MazePoint, with terrain: MazeCell) -> Bool {
        var changed = false
        for point in Self.cellsOnLine(from: start, to: end) {
            guard grid.contains(point), !grid.isOnBorder(point),
                  point != grid.start, point != grid.goal, grid[point] != terrain
            else { continue }
            grid[point] = terrain
            paintedCells[grid.index(of: point)] = terrain
            changed = true
        }
        return changed
    }

    /// Moves an endpoint. Dragging only lands on passable cells, while
    /// placing with a tool may clear a wall to make room.
    private func move(_ endpoint: MazeEndpoint, to cell: MazePoint, clearingWalls: Bool) -> Bool {
        guard grid.contains(cell), !grid.isOnBorder(cell), cell != grid.start, cell != grid.goal else { return false }
        if !grid.isPassable(cell) {
            guard clearingWalls else { return false }
            grid[cell] = .open
            paintedCells[grid.index(of: cell)] = .open
        }
        switch endpoint {
        case .start:
            grid.start = cell
            movedStart = cell
        case .goal:
            grid.goal = cell
            movedGoal = cell
        }
        return true
    }

    private func gridDidChange() {
        topology = grid.topology
        refreshComparison()
        resolveInstantly()
    }

    /// The cells from `start` to `end` on a four-connected digital line. At
    /// each step it moves along whichever axis keeps it closer to the true line.
    static func cellsOnLine(from start: MazePoint, to end: MazePoint) -> [MazePoint] {
        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let stepX = end.x > start.x ? 1 : -1
        let stepY = end.y > start.y ? 1 : -1
        var point = start
        var points = [point]
        var movedX = 0
        var movedY = 0
        while movedX < dx || movedY < dy {
            if (1 + 2 * movedX) * dy < (1 + 2 * movedY) * dx {
                point.x += stepX
                movedX += 1
            } else {
                point.y += stepY
                movedY += 1
            }
            points.append(point)
        }
        return points
    }
}
