/// Sorts that insert each element into an already sorted run.
enum InsertionSorts {
    /// Grows a sorted prefix. Each new element sinks left by swapping with
    /// larger neighbours, so sorted input costs exactly n − 1 comparisons.
    static func insertion(_ a: inout SortRecorder) {
        guard a.count > 1 else { return }
        for i in 1..<a.count {
            a.mark(.range(0..<(i + 1)))
            var j = i
            while j > 0 && a.less(j, j - 1) {
                a.swapAt(j - 1, j)
                j -= 1
            }
        }
    }

    /// Insertion sort over a decreasing sequence of gaps. Each pass leaves
    /// the array "gap-sorted", and the final pass (gap 1) is a plain insertion
    /// sort over data that is nearly in order.
    static func shell(_ a: inout SortRecorder) {
        let n = a.count
        for gap in ciuraGaps(below: n) {
            a.mark(.gap(gap))
            for i in gap..<n {
                var j = i
                while j >= gap && a.less(j, j - gap) {
                    a.swapAt(j - gap, j)
                    j -= gap
                }
            }
        }
        a.mark(.gap(nil))
    }

    /// Marcin Ciura's experimentally tuned gaps (2001), extended past 701 by
    /// the customary factor of 2.25. Returns the gaps smaller than `n`,
    /// largest first.
    static func ciuraGaps(below n: Int) -> [Int] {
        var gaps = [1, 4, 10, 23, 57, 132, 301, 701]
        while let last = gaps.last, last < n {
            gaps.append(last * 9 / 4)
        }
        return gaps.filter { $0 < n }.reversed()
    }
}
