/// One element touched by one replayed operation: what a visualizer lights up
/// and a sonifier plays.
public struct SortTouch: Hashable, Sendable {
    public enum Kind: UInt8, CaseIterable, Sendable {
        case compare
        case swap
        case write
        case read
    }

    public var kind: Kind
    /// The index that was touched.
    public var index: Int
    /// The element at `index` once the operation has run.
    public var value: Int

    public init(kind: Kind, index: Int, value: Int) {
        self.kind = kind
        self.index = index
        self.value = value
    }
}

/// Plays a `SortTrace` back onto a working copy of its input, one operation
/// at a time or thousands at once.
///
///     var replayer = SortReplayer(trace: SortAlgorithm.heap.trace(of: input))
///     while !replayer.isFinished {
///         replayer.advance(steps: 50) { touch in highlight(touch.index) }
///         draw(replayer.values)
///     }
///
/// Markers in the trace are applied as soon as they are reached and cost no
/// steps, so `focus` always describes the operation that comes next.
public struct SortReplayer: Sendable {
    /// The trace being replayed.
    public let trace: SortTrace
    /// The array as it stands after the operations replayed so far.
    public private(set) var values: [Int]
    /// Tallies of the operations replayed so far.
    public private(set) var counts = SortCounts()
    /// What the algorithm is working on. Cleared when the replay finishes.
    public private(set) var focus = SortFocus()
    /// The index in `trace.operations` of the next operation to apply.
    public private(set) var cursor = 0

    public init(trace: SortTrace) {
        self.trace = trace
        self.values = trace.input
        applyMarkers()
    }

    /// True once every operation has been applied.
    public var isFinished: Bool {
        cursor >= trace.operations.count
    }

    /// The number of steps (operations that touch the array) applied so far.
    public var stepsTaken: Int {
        counts.steps
    }

    /// The fraction of steps applied so far, from 0 to 1.
    public var progress: Double {
        let total = trace.counts.steps
        return total == 0 ? 1 : Double(counts.steps) / Double(total)
    }

    /// Applies up to `steps` operations, calling `onTouch` for every element
    /// they touch: two for a comparison or swap, one for a write or read.
    /// Returns the number of steps applied, which is less than requested only
    /// when the trace runs out.
    @discardableResult
    public mutating func advance(steps: Int, onTouch: (SortTouch) -> Void) -> Int {
        let operations = trace.operations
        var taken = 0
        while taken < steps, cursor < operations.count {
            let operation = operations[cursor]
            cursor += 1
            counts.record(operation)
            switch operation {
            case let .compare(i, j):
                onTouch(SortTouch(kind: .compare, index: i, value: values[i]))
                onTouch(SortTouch(kind: .compare, index: j, value: values[j]))
            case let .swap(i, j):
                values.swapAt(i, j)
                onTouch(SortTouch(kind: .swap, index: i, value: values[i]))
                onTouch(SortTouch(kind: .swap, index: j, value: values[j]))
            case let .write(index, value):
                values[index] = value
                onTouch(SortTouch(kind: .write, index: index, value: value))
            case let .read(index):
                onTouch(SortTouch(kind: .read, index: index, value: values[index]))
            case let .mark(marker):
                focus.apply(marker)
                continue
            }
            taken += 1
        }
        applyMarkers()
        return taken
    }

    /// Applies up to `steps` operations without reporting touches.
    @discardableResult
    public mutating func advance(steps: Int) -> Int {
        advance(steps: steps) { _ in }
    }

    /// Applies the next operation. Returns false if the replay had already
    /// finished.
    @discardableResult
    public mutating func step(onTouch: (SortTouch) -> Void = { _ in }) -> Bool {
        advance(steps: 1, onTouch: onTouch) == 1
    }

    /// Applies every remaining operation.
    public mutating func finish() {
        advance(steps: .max)
    }

    /// Returns to the unsorted input.
    public mutating func rewind() {
        values = trace.input
        counts = SortCounts()
        focus = SortFocus()
        cursor = 0
        applyMarkers()
    }

    /// Moves to the moment after `step` steps have been applied, replaying
    /// from the start if that lies in the past.
    public mutating func seek(toStep step: Int) {
        let target = max(0, step)
        if target < counts.steps {
            rewind()
        }
        advance(steps: target - counts.steps)
    }

    /// Applies any markers waiting at the cursor, so `focus` describes the
    /// next operation, and clears the focus once the replay is over.
    private mutating func applyMarkers() {
        let operations = trace.operations
        while cursor < operations.count, case let .mark(marker) = operations[cursor] {
            focus.apply(marker)
            cursor += 1
        }
        if cursor >= operations.count {
            focus = SortFocus()
        }
    }
}
