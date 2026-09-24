/// A search trace re-indexed for playback. It records when each cell was
/// discovered and expanded, measured in *steps*. Step `k` is the moment
/// after the `k`-th expansion and the discoveries it caused. At step 0 only
/// the starting cells have been discovered.
///
/// Cells are identified by their index in ``MazeGrid/cells``.
public struct SearchTimeline: Hashable, Sendable {
    /// Expanded cells, in expansion order.
    public let expansionOrder: [Int32]
    /// Parallel to ``expansionOrder``: whether the goal-side search of a
    /// bidirectional search made the expansion.
    public let expansionFromGoal: [Bool]
    /// Discovered cells, in discovery order.
    public let discoveryOrder: [Int32]
    /// Parallel to ``discoveryOrder``: the step at which each discovery happened.
    /// The values never decrease.
    public let discoveryStep: [Int32]
    /// Parallel to ``discoveryOrder``: whether the goal-side search made the discovery.
    public let discoveryFromGoal: [Bool]
    /// For every cell, the step at which it was expanded, counted from 1, or
    /// 0 if it never was.
    public let expansionStep: [Int32]

    public init(trace: SearchTrace, grid: MazeGrid) {
        var expansionOrder: [Int32] = []
        var expansionFromGoal: [Bool] = []
        var discoveryOrder: [Int32] = []
        var discoveryStep: [Int32] = []
        var discoveryFromGoal: [Bool] = []
        var expansionStep = [Int32](repeating: 0, count: grid.cellCount)
        expansionOrder.reserveCapacity(trace.stats.nodesExpanded)
        expansionFromGoal.reserveCapacity(trace.stats.nodesExpanded)
        discoveryOrder.reserveCapacity(trace.stats.nodesDiscovered)
        discoveryStep.reserveCapacity(trace.stats.nodesDiscovered)
        discoveryFromGoal.reserveCapacity(trace.stats.nodesDiscovered)

        var step: Int32 = 0
        for event in trace.events {
            let cell = Int32(grid.index(of: event.point))
            switch event.kind {
            case .expanded:
                step += 1
                expansionOrder.append(cell)
                expansionFromGoal.append(event.fromGoal)
                expansionStep[Int(cell)] = step
            case .discovered:
                discoveryOrder.append(cell)
                discoveryStep.append(step)
                discoveryFromGoal.append(event.fromGoal)
            }
        }
        self.expansionOrder = expansionOrder
        self.expansionFromGoal = expansionFromGoal
        self.discoveryOrder = discoveryOrder
        self.discoveryStep = discoveryStep
        self.discoveryFromGoal = discoveryFromGoal
        self.expansionStep = expansionStep
    }

    /// The number of steps, which is also the number of expansions.
    public var stepCount: Int { expansionOrder.count }

    /// How many discoveries have happened by `step`. Those discoveries are the
    /// first entries of ``discoveryOrder``. Found by binary search.
    public func discoveryCount(atStep step: Int) -> Int {
        let target = Int32(clamping: step)
        var low = 0
        var high = discoveryStep.count
        while low < high {
            let middle = (low + high) / 2
            if discoveryStep[middle] <= target {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// Whether the cell has been expanded by `step`.
    public func isExpanded(_ cell: Int, atStep step: Int) -> Bool {
        let expandedAt = expansionStep[cell]
        return expandedAt > 0 && Int(expandedAt) <= step
    }

    /// The cells on the frontier at `step`: discovered but not yet expanded,
    /// in discovery order.
    public func frontier(atStep step: Int) -> [Int] {
        discoveryOrder.prefix(discoveryCount(atStep: step))
            .map { Int($0) }
            .filter { !isExpanded($0, atStep: step) }
    }
}
