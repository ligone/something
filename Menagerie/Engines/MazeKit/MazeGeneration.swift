/// The complete, replayable record of generating one maze.
///
/// A generator starts from ``initial`` and emits ``steps`` in order. Replaying
/// every step on the initial grid reproduces ``maze`` exactly, so a UI can
/// animate carving at any speed and still land on the true result.
public struct MazeGeneration: Hashable, Sendable {
    /// One recorded action of a generator.
    public enum Step: Hashable, Sendable {
        /// Changes a cell's terrain. This is the only kind of step that alters the maze.
        case set(MazePoint, MazeCell)
        /// A cell joins the generator's working set: the recursive
        /// backtracker's stack, Prim's frontier or Wilson's current walk.
        case mark(MazePoint)
        /// A cell leaves the working set.
        case unmark(MazePoint)

        /// The cell the step acts on.
        public var point: MazePoint {
            switch self {
            case let .set(point, _), let .mark(point), let .unmark(point):
                return point
            }
        }
    }

    /// The stages of generation, in the order they run.
    public enum Phase: Hashable, Sendable {
        /// The chosen algorithm builds the maze.
        case carving
        /// Mud patches are spread over the floor.
        case spreadingMud
        /// Dead ends are knocked through to add loops.
        case braiding
    }

    /// The algorithm that produced this maze.
    public let generator: MazeGenerator
    /// The seed that produced this maze.
    public let seed: UInt64
    /// The options that produced this maze.
    public let options: MazeGenerator.Options
    /// The grid before the first step.
    public let initial: MazeGrid
    /// Every step, in order.
    public let steps: [Step]
    /// The finished maze, equal to ``initial`` with every step applied.
    public let maze: MazeGrid
    /// The index of the first mud step. It equals `steps.count` if no mud was spread.
    public let mudStart: Int
    /// The index of the first braiding step. It equals `steps.count` if no loops were added.
    public let braidingStart: Int

    /// The phase that a step belongs to.
    public func phase(ofStep index: Int) -> Phase {
        if index >= braidingStart { return .braiding }
        if index >= mudStart { return .spreadingMud }
        return .carving
    }

    /// The grid after replaying the first `count` steps.
    public func grid(afterSteps count: Int) -> MazeGrid {
        var grid = initial
        for step in steps.prefix(max(0, count)) {
            grid.apply(step)
        }
        return grid
    }
}

/// The maze-generation algorithms. Each is seeded and deterministic.
public enum MazeGenerator: String, CaseIterable, Identifiable, Sendable {
    /// Depth-first carving with an explicit stack. It makes long, winding
    /// corridors with few branches.
    case recursiveBacktracker
    /// Randomized Prim's: grows the maze from a random frontier, which makes
    /// many short branches and dead ends.
    case prim
    /// Randomized Kruskal's: removes walls in random order and uses union–find
    /// to refuse any wall that would close a loop.
    case kruskal
    /// Wilson's: loop-erased random walks, which draw a *uniform* spanning
    /// tree, so every perfect maze is equally likely.
    case wilson
    /// Splits an open field with walls, each pierced by a single gap, and recurses.
    case recursiveDivision
    /// Random rubble scattered over an open field.
    case obstacles
    /// An open field with walls only around the border.
    case empty

    public var id: String { rawValue }

    /// A short display name.
    public var name: String {
        switch self {
        case .recursiveBacktracker: return "Recursive backtracker"
        case .prim: return "Prim's"
        case .kruskal: return "Kruskal's"
        case .wilson: return "Wilson's"
        case .recursiveDivision: return "Recursive division"
        case .obstacles: return "Scattered obstacles"
        case .empty: return "Empty field"
        }
    }

    /// A one-line description of how the algorithm works.
    public var summary: String {
        switch self {
        case .recursiveBacktracker: return "Depth-first carving: long corridors, few branches."
        case .prim: return "Grows from a random frontier: bushy, short dead ends."
        case .kruskal: return "Random walls fall unless union–find sees a loop."
        case .wilson: return "Loop-erased random walks: a uniform spanning tree."
        case .recursiveDivision: return "Splits the field with walls, one gap in each."
        case .obstacles: return "Random rubble on an open floor."
        case .empty: return "Open floor to paint on."
        }
    }

    /// Whether the algorithm carves a *perfect* maze, with exactly one route
    /// between any two cells, before loops are added.
    public var carvesPerfectMaze: Bool {
        switch self {
        case .obstacles, .empty: return false
        default: return true
        }
    }

    /// Adjustments applied after the main algorithm runs.
    public struct Options: Hashable, Sendable {
        /// The fraction of dead ends, from 0 to 1, to knock through into a
        /// neighbouring passage. Each one adds a loop, so different searches
        /// can find different routes. Raising it only ever removes more walls.
        public var braid: Double
        /// The fraction of the floor, from 0 to 1, to cover with mud patches.
        public var mud: Double

        public init(braid: Double = 0, mud: Double = 0) {
            self.braid = braid
            self.mud = mud
        }
    }

    /// Generates a maze.
    ///
    /// Even dimensions are rounded up to the next odd number, so the maze
    /// keeps a wall border. Mud is spread before braiding, and each phase
    /// draws from its own random stream. As a result, a larger `braid` with
    /// the same seed opens a superset of the same walls, and toggling mud
    /// leaves the walls untouched.
    public func generate(width: Int, height: Int, seed: UInt64, options: Options = Options()) -> MazeGeneration {
        let width = max(3, width | 1)
        let height = max(3, height | 1)
        let root = MazeRandom(seed: seed)
        var carveRandom = root.fork(0xC4E5)
        var mudRandom = root.fork(0x3D0D)
        var braidRandom = root.fork(0xB4A1)

        var recorder: GenerationRecorder
        switch self {
        case .recursiveBacktracker:
            recorder = GenerationRecorder(MazeGrid(width: width, height: height))
            PerfectMazeCarver.recursiveBacktracker(&recorder, random: &carveRandom)
        case .prim:
            recorder = GenerationRecorder(MazeGrid(width: width, height: height))
            PerfectMazeCarver.prim(&recorder, random: &carveRandom)
        case .kruskal:
            recorder = GenerationRecorder(RoomLattice.roomsOnly(width: width, height: height))
            PerfectMazeCarver.kruskal(&recorder, random: &carveRandom)
        case .wilson:
            recorder = GenerationRecorder(MazeGrid(width: width, height: height))
            PerfectMazeCarver.wilson(&recorder, random: &carveRandom)
        case .recursiveDivision:
            recorder = GenerationRecorder(MazeGrid.openField(width: width, height: height))
            PerfectMazeCarver.recursiveDivision(&recorder, random: &carveRandom)
        case .obstacles:
            recorder = OpenFieldBuilder.obstacles(width: width, height: height, random: &carveRandom)
        case .empty:
            recorder = GenerationRecorder(MazeGrid.openField(width: width, height: height))
        }

        let mudStart = recorder.steps.count
        MazeFinishing.spreadMud(&recorder, coverage: options.mud, random: &mudRandom)
        let braidingStart = recorder.steps.count
        MazeFinishing.braid(&recorder, fraction: options.braid, random: &braidRandom)

        return MazeGeneration(
            generator: self,
            seed: seed,
            options: options,
            initial: recorder.initial,
            steps: recorder.steps,
            maze: recorder.grid,
            mudStart: mudStart,
            braidingStart: braidingStart
        )
    }
}
