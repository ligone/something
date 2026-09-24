/// Everything a search did: every cell it touched, in order, plus the route it
/// found and summary statistics.
public struct SearchTrace: Hashable, Sendable {
    /// One moment in a search.
    public struct Event: Hashable, Sendable {
        public enum Kind: UInt8, Hashable, Sendable {
            /// The cell joined the frontier (the open set) for the first time.
            case discovered
            /// The cell left the frontier and its neighbours were examined.
            case expanded
        }

        public var kind: Kind
        public var point: MazePoint
        /// `true` for events from the goal-side half of a bidirectional search.
        public var fromGoal: Bool

        public init(kind: Kind, point: MazePoint, fromGoal: Bool = false) {
            self.kind = kind
            self.point = point
            self.fromGoal = fromGoal
        }
    }

    /// Summary statistics.
    public struct Stats: Hashable, Sendable {
        /// Cells removed from the frontier and expanded, the goal included.
        public var nodesExpanded: Int
        /// Distinct cells that ever entered the frontier.
        public var nodesDiscovered: Int
        /// The number of moves in the path, or 0 when no path was found.
        public var pathLength: Int
        /// The summed cost of every cell the path steps onto, which excludes
        /// the start. It is 0 when no path was found.
        public var pathCost: Int
        /// Whether the search reached the goal.
        public var foundGoal: Bool

        public init(nodesExpanded: Int, nodesDiscovered: Int, pathLength: Int, pathCost: Int, foundGoal: Bool) {
            self.nodesExpanded = nodesExpanded
            self.nodesDiscovered = nodesDiscovered
            self.pathLength = pathLength
            self.pathCost = pathCost
            self.foundGoal = foundGoal
        }
    }

    /// The algorithm that produced the trace.
    public let solver: MazeSolver
    /// Every discovery and expansion, in order. Each expansion is followed by
    /// the discoveries it caused.
    public let events: [Event]
    /// The route from start to goal, both included, or empty when the goal is unreachable.
    public let path: [MazePoint]
    public let stats: Stats

    public init(solver: MazeSolver, events: [Event], path: [MazePoint], stats: Stats) {
        self.solver = solver
        self.events = events
        self.path = path
        self.stats = stats
    }
}
