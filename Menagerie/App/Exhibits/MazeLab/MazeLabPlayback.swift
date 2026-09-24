import Foundation
import MazeKit

/// The replay of a ``MazeGeneration`` in progress. It holds the working grid
/// and the generator's working set as of the playback cursor.
struct MazeCarvingPlayback {
    let generation: MazeGeneration
    /// The initial grid with the first ``applied`` steps replayed.
    private(set) var grid: MazeGrid
    /// How many steps have been replayed.
    private(set) var applied = 0
    /// Which cells are in the generator's working set, indexed like `MazeGrid.cells`.
    private(set) var marked: [Bool]
    private(set) var markedCount = 0
    private var cursor = 0.0

    init(_ generation: MazeGeneration) {
        self.generation = generation
        grid = generation.initial
        marked = Array(repeating: false, count: generation.initial.cellCount)
    }

    var isFinished: Bool { applied >= generation.steps.count }

    /// The fraction of steps replayed, from 0 to 1.
    var progress: Double {
        generation.steps.isEmpty ? 1 : Double(applied) / Double(generation.steps.count)
    }

    /// The cell the most recent step touched: the generator's "hand".
    var head: MazePoint? {
        applied > 0 ? generation.steps[applied - 1].point : nil
    }

    /// The phase of the most recent step.
    var phase: MazeGeneration.Phase {
        generation.phase(ofStep: max(applied - 1, 0))
    }

    /// Moves the cursor forward by a possibly fractional number of steps and
    /// replays every step it passes.
    mutating func advance(by steps: Double) {
        cursor += steps
        let target = min(Int(cursor), generation.steps.count)
        while applied < target {
            let step = generation.steps[applied]
            switch step {
            case let .set(point, terrain):
                grid[point] = terrain
            case let .mark(point):
                marked[grid.index(of: point)] = true
                markedCount += 1
            case let .unmark(point):
                marked[grid.index(of: point)] = false
                markedCount -= 1
            }
            applied += 1
        }
    }
}

/// A solved search and how much of it has been revealed.
struct MazeSearchPlayback {
    /// Shades per colour ramp. The explored region is coloured by expansion
    /// order in this many bands.
    static let shadeCount = 40

    let trace: SearchTrace
    let timeline: SearchTimeline
    /// For each expansion in order, its shade. Values below ``shadeCount`` are
    /// on the forward ramp; values from ``shadeCount`` up are on the ramp for
    /// the goal side of a bidirectional search.
    let shades: [UInt8]
    private var cursor: Double

    init(trace: SearchTrace, grid: MazeGrid, finished: Bool) {
        self.trace = trace
        timeline = SearchTimeline(trace: trace, grid: grid)
        shades = Self.shades(for: timeline)
        cursor = finished ? Double(timeline.stepCount) : 0
    }

    /// How many expansions are on show.
    var step: Int { min(Int(cursor), timeline.stepCount) }

    var isFinished: Bool { step >= timeline.stepCount }

    mutating func advance(by steps: Double) {
        cursor = min(cursor + steps, Double(timeline.stepCount))
    }

    mutating func finish() {
        cursor = Double(timeline.stepCount)
    }

    /// Normalises each side's expansion order onto its own ramp, so both
    /// halves of a bidirectional search run the full gradient.
    private static func shades(for timeline: SearchTimeline) -> [UInt8] {
        let backwardTotal = timeline.expansionFromGoal.reduce(0) { $0 + ($1 ? 1 : 0) }
        let forwardTotal = timeline.stepCount - backwardTotal
        var forwardRank = 0
        var backwardRank = 0
        return timeline.expansionFromGoal.map { fromGoal in
            let rank = fromGoal ? backwardRank : forwardRank
            let total = fromGoal ? backwardTotal : forwardTotal
            if fromGoal { backwardRank += 1 } else { forwardRank += 1 }
            let fraction = total > 1 ? Double(rank) / Double(total - 1) : 0
            let shade = min(Int(fraction * Double(shadeCount - 1) + 0.5), shadeCount - 1)
            return UInt8(fromGoal ? shade + shadeCount : shade)
        }
    }
}
