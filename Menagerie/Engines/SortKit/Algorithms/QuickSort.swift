/// Quicksort with median-of-three pivots and Sedgewick's two-pointer
/// partition.
enum QuickSort {
    /// Ranges at least this long take the ninther rather than a plain median
    /// of three, as in Bentley and McIlroy's "Engineering a Sort Function".
    static let nintherThreshold = 40

    static func sort(_ a: inout SortRecorder) {
        sort(&a, lo: 0, hi: a.count - 1)
    }

    /// Sorts `lo...hi`. It recurses into the smaller side and loops on the
    /// larger one, so the stack never grows deeper than log₂ n frames.
    private static func sort(_ a: inout SortRecorder, lo: Int, hi: Int) {
        var lo = lo
        var hi = hi
        while lo < hi {
            a.mark(.range(lo..<(hi + 1)))
            let pivot = partition(&a, lo: lo, hi: hi)
            if pivot - lo < hi - pivot {
                sort(&a, lo: lo, hi: pivot - 1)
                lo = pivot + 1
            } else {
                sort(&a, lo: pivot + 1, hi: hi)
                hi = pivot - 1
            }
        }
    }

    /// Moves a well-chosen pivot to `lo`, then sweeps two pointers inward:
    /// `i` stops at elements that don't belong left of the pivot, `j` at
    /// elements that don't belong right of it, and the pair is swapped. Both
    /// pointers stop on elements equal to the pivot, which keeps partitions
    /// balanced when there are many duplicates. Returns the pivot's final
    /// index.
    private static func partition(_ a: inout SortRecorder, lo: Int, hi: Int) -> Int {
        a.mark(.pivot(nil))
        if hi - lo >= 2 {
            a.swapAt(lo, choosePivot(&a, lo: lo, hi: hi))
        }
        a.mark(.pivot(lo))

        var i = lo
        var j = hi + 1
        while true {
            i += 1
            while a.less(i, lo) {
                if i == hi { break }
                i += 1
            }
            j -= 1
            while j > lo && a.less(lo, j) {
                j -= 1
            }
            if i >= j { break }
            a.swapAt(i, j)
        }
        a.swapAt(lo, j)
        a.mark(.pivot(j))
        return j
    }

    /// The median of the first, middle and last elements; on long ranges,
    /// Tukey's ninther: the median of three such medians taken from the
    /// start, middle and end.
    ///
    /// A plain median of three is not enough on its own. The final swap of
    /// each partition parks a large element at the front of the left part,
    /// so reversed input decays into rotated runs like `[8, 1, 2, …, 7]`,
    /// where first, middle and last always yield the second-largest value.
    /// The ninther samples past the parked element and splits them evenly.
    private static func choosePivot(_ a: inout SortRecorder, lo: Int, hi: Int) -> Int {
        let mid = lo + (hi - lo) / 2
        let count = hi - lo + 1
        guard count >= nintherThreshold else {
            return medianOfThree(&a, lo, mid, hi)
        }
        let step = count / 8
        let first = medianOfThree(&a, lo, lo + step, lo + 2 * step)
        let middle = medianOfThree(&a, mid - step, mid, mid + step)
        let last = medianOfThree(&a, hi - 2 * step, hi - step, hi)
        return medianOfThree(&a, first, middle, last)
    }

    /// The index holding the median of the elements at `x`, `y` and `z`,
    /// found with two or three comparisons.
    private static func medianOfThree(_ a: inout SortRecorder, _ x: Int, _ y: Int, _ z: Int) -> Int {
        if a.less(x, y) {
            if a.less(y, z) { return y }
            return a.less(x, z) ? z : x
        } else {
            if a.less(x, z) { return x }
            return a.less(y, z) ? z : y
        }
    }
}
