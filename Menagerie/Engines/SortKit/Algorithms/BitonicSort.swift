/// Batcher's bitonic sorting network, generalized to any length.
///
/// The classic network needs a power-of-two length. This variant (after
/// H. W. Lang) sorts the first half descending and the second half ascending,
/// which leaves a bitonic sequence, then merges it with compare-exchanges at a
/// distance of the largest power of two below the length. The sequence of
/// comparisons depends only on the length, never on the data.
enum BitonicSort {
    static func sort(_ a: inout SortRecorder) {
        sort(&a, lo: 0, count: a.count, ascending: true)
    }

    private static func sort(_ a: inout SortRecorder, lo: Int, count: Int, ascending: Bool) {
        guard count > 1 else { return }
        let half = count / 2
        sort(&a, lo: lo, count: half, ascending: !ascending)
        sort(&a, lo: lo + half, count: count - half, ascending: ascending)
        a.mark(.range(lo..<(lo + count)))
        merge(&a, lo: lo, count: count, ascending: ascending)
    }

    /// Sorts the bitonic sequence `lo..<(lo + count)` in the given direction.
    private static func merge(_ a: inout SortRecorder, lo: Int, count: Int, ascending: Bool) {
        guard count > 1 else { return }
        let distance = greatestPowerOfTwo(below: count)
        for i in lo..<(lo + count - distance) {
            let outOfOrder = ascending ? a.less(i + distance, i) : a.less(i, i + distance)
            if outOfOrder {
                a.swapAt(i, i + distance)
            }
        }
        merge(&a, lo: lo, count: distance, ascending: ascending)
        merge(&a, lo: lo + distance, count: count - distance, ascending: ascending)
    }

    /// The largest power of two strictly less than `n` (for n ≥ 2).
    static func greatestPowerOfTwo(below n: Int) -> Int {
        var power = 1
        while power < n {
            power <<= 1
        }
        return power >> 1
    }
}
