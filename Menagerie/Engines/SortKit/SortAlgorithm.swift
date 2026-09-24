/// The sorting algorithms SortKit can trace.
///
///     let trace = SortAlgorithm.quick.trace(of: [3, 1, 2])
///     var replayer = SortReplayer(trace: trace)
///     replayer.advance(steps: 10) { touch in light(touch.index) }
///
/// Metadata such as `name`, `complexity` and `isStable` lives in
/// `SortAlgorithm+Info.swift`.
public enum SortAlgorithm: String, CaseIterable, Identifiable, Sendable {
    // Exchange sorts
    case bubble
    case cocktailShaker
    case gnome
    case comb
    // Insertion sorts
    case insertion
    case shell
    // Selection sorts
    case selection
    case cycle
    case heap
    // Divide and conquer
    case merge
    case quick
    // Distribution
    case radixLSD
    // Sorting networks
    case bitonic

    public var id: String { rawValue }

    /// Sorts a copy of `input` and records every comparison, swap, read and
    /// write the algorithm makes, plus markers that explain its progress.
    ///
    /// Replaying the trace's operations on `input` always yields
    /// `input.sorted()`.
    public func trace(of input: [Int]) -> SortTrace {
        trace(of: input, sortKey: { $0 })
    }

    /// Like `trace(of:)`, but orders elements by `sortKey(element)` rather
    /// than by the element itself. Elements with equal keys may be told apart
    /// afterwards, which is how the tests check stability.
    func trace(of input: [Int], sortKey: @escaping (Int) -> Int) -> SortTrace {
        var recorder = SortRecorder(input, sortKey: sortKey)
        run(&recorder)
        return SortTrace(
            algorithm: self,
            input: input,
            operations: recorder.operations,
            output: recorder.values
        )
    }

    private func run(_ recorder: inout SortRecorder) {
        switch self {
        case .bubble: ExchangeSorts.bubble(&recorder)
        case .cocktailShaker: ExchangeSorts.cocktailShaker(&recorder)
        case .gnome: ExchangeSorts.gnome(&recorder)
        case .comb: ExchangeSorts.comb(&recorder)
        case .insertion: InsertionSorts.insertion(&recorder)
        case .shell: InsertionSorts.shell(&recorder)
        case .selection: SelectionSorts.selection(&recorder)
        case .cycle: SelectionSorts.cycle(&recorder)
        case .heap: SelectionSorts.heap(&recorder)
        case .merge: MergeSort.sort(&recorder)
        case .quick: QuickSort.sort(&recorder)
        case .radixLSD: RadixSort.leastSignificantDigitFirst(&recorder)
        case .bitonic: BitonicSort.sort(&recorder)
        }
    }
}
