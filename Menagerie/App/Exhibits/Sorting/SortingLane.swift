import SortKit

/// Why a bar is lit up.
enum SortingHighlight: UInt8, CaseIterable {
    case compare
    /// A swap or a write.
    case move
    case read
    /// Passed by the verification sweep.
    case verified
    /// Found out of order by the verification sweep. It never happens, but
    /// the sweep genuinely checks.
    case mismatch

    init(_ kind: SortTouch.Kind) {
        switch kind {
        case .compare: self = .compare
        case .swap, .write: self = .move
        case .read: self = .read
        }
    }
}

/// One array being sorted on the stage: its replay, plus everything needed to
/// draw it, such as which bars are glowing and how far the verification
/// sweep has got.
struct SortingLane: Identifiable {
    enum Phase {
        /// Not a single step taken yet.
        case waiting
        case sorting
        /// Replay finished; the green sweep is checking the result.
        case verifying
        /// Sorted and verified.
        case sorted
    }

    /// The lane's position on the stage.
    let id: Int
    let algorithm: SortAlgorithm
    let input: [Int]
    let valueRange: ClosedRange<Int>

    private(set) var replayer: SortReplayer?
    private(set) var phase = Phase.waiting
    /// Glow per index, from 1 when touched down to 0.
    private(set) var heat: [Float]
    /// What last touched each index.
    private(set) var highlight: [SortingHighlight]
    /// The touches of the latest step, drawn at full strength while paused.
    private(set) var latest: [SortTouch] = []
    /// The verification sweep's front, in elements.
    private(set) var sweep: Double = 0
    /// False if the sweep found a pair out of order.
    private(set) var isVerified = true

    init(id: Int, algorithm: SortAlgorithm, input: [Int]) {
        self.id = id
        self.algorithm = algorithm
        self.input = input
        valueRange = (input.min() ?? 0)...(input.max() ?? 1)
        heat = Array(repeating: 0, count: input.count)
        highlight = Array(repeating: .compare, count: input.count)
    }

    // MARK: Reading

    var values: [Int] { replayer?.values ?? input }
    var counts: SortCounts { replayer?.counts ?? SortCounts() }
    var isPrepared: Bool { replayer != nil }
    var totalSteps: Int? { replayer?.trace.stepCount }
    var progress: Double { phase == .waiting ? 0 : replayer?.progress ?? 0 }

    /// What the algorithm is working on, while it is working.
    var focus: SortFocus {
        phase == .sorting ? replayer?.focus ?? SortFocus() : SortFocus()
    }

    /// The value's position within the input's range, from 0 to 1.
    func level(of value: Int) -> Double {
        let span = valueRange.upperBound - valueRange.lowerBound
        guard span > 0 else { return 1 }
        return Double(value - valueRange.lowerBound) / Double(span)
    }

    // MARK: Replaying

    mutating func install(_ trace: SortTrace) {
        replayer = SortReplayer(trace: trace)
    }

    /// Replays up to `steps` operations, appending every touch to `touches`
    /// and lighting up the touched bars. Moves on to the verification sweep
    /// when the replay ends.
    mutating func advance(steps: Int, touches: inout [SortTouch]) {
        guard replayer != nil, phase == .waiting || phase == .sorting else { return }
        let start = touches.count
        let taken = replayer?.advance(steps: steps) { touches.append($0) } ?? 0

        for touch in touches[start...] {
            heat[touch.index] = 1
            highlight[touch.index] = SortingHighlight(touch.kind)
        }
        if taken > 0 {
            phase = .sorting
            // A comparison or swap touches two bars; a write or read, one.
            let last = touches.last?.kind
            let width = last == .compare || last == .swap ? 2 : 1
            latest = Array(touches.suffix(min(width, touches.count - start)))
        }
        if replayer?.isFinished == true {
            phase = .verifying
            sweep = 0
            latest = []
        }
    }

    /// Moves the verification sweep forward by `distance` elements, checking
    /// each newly passed pair and collecting the passed indices.
    mutating func advanceSweep(by distance: Double, passed: inout [Int]) {
        guard phase == .verifying else { return }
        let values = self.values
        let from = Int(sweep)
        sweep = min(Double(values.count), sweep + distance)
        let to = Int(sweep)
        if from < to {
            for index in from..<to {
                let ordered = index == 0 || values[index - 1] <= values[index]
                if !ordered { isVerified = false }
                heat[index] = 1
                highlight[index] = ordered ? .verified : .mismatch
                passed.append(index)
            }
        }
        if to >= values.count {
            phase = .sorted
        }
    }

    /// Fades every glow by the given factors (sweep highlights linger longer).
    /// Returns whether anything is still glowing.
    mutating func fade(normal: Float, lingering: Float) -> Bool {
        var glowing = false
        for index in heat.indices where heat[index] > 0 {
            let kind = highlight[index]
            let factor = kind == .verified || kind == .mismatch ? lingering : normal
            let faded = heat[index] * factor
            heat[index] = faded < 0.01 ? 0 : faded
            glowing = glowing || faded >= 0.01
        }
        return glowing
    }

    /// Returns to the unsorted input, keeping the prepared trace.
    mutating func rewind() {
        replayer?.rewind()
        phase = .waiting
        heat = Array(repeating: 0, count: input.count)
        latest = []
        sweep = 0
        isVerified = true
    }

    /// Forgets the latest step's highlight.
    mutating func clearLatest() {
        latest = []
    }
}
