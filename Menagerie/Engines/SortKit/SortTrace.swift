/// Tallies of the operations in a trace, or in the part of it replayed so far.
public struct SortCounts: Hashable, Sendable {
    public var comparisons: Int
    public var swaps: Int
    /// Single-element writes (`SortOperation.write`). Swaps are counted
    /// separately; see `arrayWrites` for the total number of stores.
    public var writes: Int
    public var reads: Int

    public init(comparisons: Int = 0, swaps: Int = 0, writes: Int = 0, reads: Int = 0) {
        self.comparisons = comparisons
        self.swaps = swaps
        self.writes = writes
        self.reads = reads
    }

    /// Every operation that touches the array; markers aren't steps.
    public var steps: Int {
        comparisons + swaps + writes + reads
    }

    /// Element stores: one per write, two per swap. This is the fairest way
    /// to compare the data movement of swap-based and buffer-based sorts.
    public var arrayWrites: Int {
        writes + 2 * swaps
    }

    /// Counts one more operation.
    public mutating func record(_ operation: SortOperation) {
        switch operation {
        case .compare: comparisons += 1
        case .swap: swaps += 1
        case .write: writes += 1
        case .read: reads += 1
        case .mark: break
        }
    }
}

/// A complete, replayable record of one algorithm sorting one input.
///
/// Produce one with `SortAlgorithm.trace(of:)`, then step through it with a
/// `SortReplayer`, as slowly or as quickly as you like.
public struct SortTrace: Sendable {
    /// The algorithm that produced the trace.
    public let algorithm: SortAlgorithm
    /// The array before sorting.
    public let input: [Int]
    /// Every operation, in order. Applying them to `input` yields `output`.
    public let operations: [SortOperation]
    /// The array after sorting.
    public let output: [Int]
    /// Totals over the whole trace.
    public let counts: SortCounts

    init(algorithm: SortAlgorithm, input: [Int], operations: [SortOperation], output: [Int]) {
        self.algorithm = algorithm
        self.input = input
        self.operations = operations
        self.output = output

        var counts = SortCounts()
        for operation in operations {
            counts.record(operation)
        }
        self.counts = counts
    }

    /// The number of operations that touch the array (markers excluded).
    public var stepCount: Int {
        counts.steps
    }
}
