/// One step of a sorting algorithm, as recorded in a `SortTrace`.
///
/// Indices always refer to the array being sorted, in the state it is in just
/// before the operation runs, so a trace can be replayed on the original input
/// one operation at a time.
public enum SortOperation: Hashable, Sendable {
    /// Compares the elements at two indices. The array doesn't change.
    case compare(Int, Int)
    /// Exchanges the elements at two indices.
    case swap(Int, Int)
    /// Stores `value` at `index`, overwriting what was there. Merge sort uses
    /// it to copy merged runs back from its buffer, radix sort to scatter
    /// values into their buckets.
    case write(index: Int, value: Int)
    /// Reads the element at an index without comparing it, like radix sort's
    /// digit-counting pass. The array doesn't change.
    case read(Int)
    /// An annotation that explains what the algorithm is doing: the pivot, the
    /// sub-array it is working on, the current gap. It touches no element and
    /// takes no time when a trace is replayed.
    case mark(SortMarker)

    /// Whether the operation touches the array. Markers don't, so replayers
    /// apply them for free rather than counting them as steps.
    public var isStep: Bool {
        if case .mark = self { return false }
        return true
    }
}

/// Annotations an algorithm drops into its trace. A `SortReplayer` folds them
/// into a `SortFocus`, which says what the algorithm is working on right now.
///
/// Each marker replaces the previous one of the same kind; passing `nil`
/// clears it.
public enum SortMarker: Hashable, Sendable {
    /// The sub-array the algorithm is working on: a partition, a merge, the
    /// unsorted part of the array or the heap.
    case range(Range<Int>?)
    /// An element the algorithm is holding on to: quicksort's pivot,
    /// selection sort's running minimum, cycle sort's cycle start.
    case pivot(Int?)
    /// The distance between compared elements in a diminishing-increment
    /// pass (Shell sort, comb sort).
    case gap(Int?)
    /// The radix digit being distributed, counting from the least significant
    /// digit, which is 0.
    case digit(Int?)
}

/// What an algorithm is focused on at one moment of a replay, assembled from
/// the markers in its trace.
public struct SortFocus: Hashable, Sendable {
    /// The sub-array being worked on.
    public var range: Range<Int>?
    /// The index of the pivot (or running minimum, or cycle start).
    public var pivot: Int?
    /// The gap of the current pass.
    public var gap: Int?
    /// The radix digit being distributed, least significant first.
    public var digit: Int?

    public init(range: Range<Int>? = nil, pivot: Int? = nil, gap: Int? = nil, digit: Int? = nil) {
        self.range = range
        self.pivot = pivot
        self.gap = gap
        self.digit = digit
    }

    /// True when no marker is active.
    public var isEmpty: Bool {
        range == nil && pivot == nil && gap == nil && digit == nil
    }

    /// Folds one marker into the focus.
    public mutating func apply(_ marker: SortMarker) {
        switch marker {
        case .range(let range): self.range = range
        case .pivot(let pivot): self.pivot = pivot
        case .gap(let gap): self.gap = gap
        case .digit(let digit): self.digit = digit
        }
    }
}
