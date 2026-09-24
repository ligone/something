/// The array an algorithm sorts, instrumented so that every access it makes
/// is recorded as a `SortOperation`.
///
/// Algorithms never touch `values` directly: they compare, swap, read and
/// write through the recorder, which keeps the trace honest. The only
/// unrecorded access is `peek`, for re-reading a value the algorithm has just
/// compared (and so has already "seen").
///
/// Elements are ordered by `sortKey(value)`. The key is the value itself for
/// normal sorting; tests pack a tag into the low bits and order by the high
/// bits to check that stable algorithms keep equal keys in order.
struct SortRecorder {
    private(set) var values: [Int]
    private(set) var operations: [SortOperation] = []
    private let sortKey: (Int) -> Int

    init(_ values: [Int], sortKey: @escaping (Int) -> Int = { $0 }) {
        self.values = values
        self.sortKey = sortKey
    }

    var count: Int { values.count }

    // MARK: Recorded accesses

    /// Records a comparison; true when the element at `i` orders strictly
    /// before the element at `j`.
    mutating func less(_ i: Int, _ j: Int) -> Bool {
        operations.append(.compare(i, j))
        return sortKey(values[i]) < sortKey(values[j])
    }

    /// Records a comparison; true when the elements at `i` and `j` have equal
    /// keys.
    mutating func equal(_ i: Int, _ j: Int) -> Bool {
        operations.append(.compare(i, j))
        return sortKey(values[i]) == sortKey(values[j])
    }

    /// Records and performs a swap. Swapping an index with itself is a no-op
    /// and isn't recorded.
    mutating func swapAt(_ i: Int, _ j: Int) {
        guard i != j else { return }
        operations.append(.swap(i, j))
        values.swapAt(i, j)
    }

    /// Records a read and returns the element.
    mutating func read(_ i: Int) -> Int {
        operations.append(.read(i))
        return values[i]
    }

    /// Records and performs a write.
    mutating func write(_ value: Int, at i: Int) {
        operations.append(.write(index: i, value: value))
        values[i] = value
    }

    /// Records an annotation.
    mutating func mark(_ marker: SortMarker) {
        operations.append(.mark(marker))
    }

    // MARK: Unrecorded bookkeeping

    /// The element at `i`, without recording an access. Only for values the
    /// algorithm has just compared.
    func peek(_ i: Int) -> Int {
        values[i]
    }

    /// The sort key of the element at `i`, without recording an access.
    func key(at i: Int) -> Int {
        sortKey(values[i])
    }

    /// The sort key of a value the algorithm holds.
    func key(of value: Int) -> Int {
        sortKey(value)
    }
}
