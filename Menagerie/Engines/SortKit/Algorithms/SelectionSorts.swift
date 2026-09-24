/// Sorts that repeatedly select the element that belongs next.
enum SelectionSorts {
    /// Finds the minimum of the unsorted suffix and swaps it to the front of
    /// the suffix. Always n(n − 1)/2 comparisons, at most n − 1 swaps.
    static func selection(_ a: inout SortRecorder) {
        let n = a.count
        guard n > 1 else { return }
        for i in 0..<(n - 1) {
            a.mark(.range(i..<n))
            var smallest = i
            a.mark(.pivot(smallest))
            for j in (i + 1)..<n {
                if a.less(j, smallest) {
                    smallest = j
                    a.mark(.pivot(smallest))
                }
            }
            a.swapAt(i, smallest)
        }
        a.mark(.pivot(nil))
    }

    /// Cycle sort, in a swap-based form that keeps the array a permutation at
    /// every step. The element parked at `start` is sent straight to its
    /// final slot (found by counting the smaller elements after it), and
    /// whatever it displaces comes back to `start`, until the element that
    /// belongs at `start` arrives. Every swap settles one element for good,
    /// so a permutation with c cycles takes exactly n − c swaps.
    static func cycle(_ a: inout SortRecorder) {
        let n = a.count
        guard n > 1 else { return }
        for start in 0..<(n - 1) {
            a.mark(.range(start..<n))
            a.mark(.pivot(start))
            while true {
                var target = start
                for i in (start + 1)..<n {
                    if a.less(i, start) {
                        target += 1
                    }
                }
                if target == start { break }
                // Skip past equal elements that already sit in this key's slots.
                while a.equal(target, start) {
                    target += 1
                }
                a.swapAt(start, target)
            }
        }
        a.mark(.pivot(nil))
    }

    /// Builds a max-heap bottom-up (Floyd's method), then repeatedly swaps the
    /// maximum at the root to the end of the shrinking heap and sifts the new
    /// root down.
    static func heap(_ a: inout SortRecorder) {
        let n = a.count
        guard n > 1 else { return }
        a.mark(.range(0..<n))
        for root in stride(from: n / 2 - 1, through: 0, by: -1) {
            siftDown(&a, from: root, end: n)
        }
        for end in stride(from: n - 1, to: 0, by: -1) {
            a.swapAt(0, end)
            a.mark(.range(0..<end))
            siftDown(&a, from: 0, end: end)
        }
    }

    /// Restores the heap property below `root` within `0..<end`.
    private static func siftDown(_ a: inout SortRecorder, from root: Int, end: Int) {
        var parent = root
        while true {
            var child = 2 * parent + 1
            guard child < end else { return }
            if child + 1 < end && a.less(child, child + 1) {
                child += 1
            }
            guard a.less(parent, child) else { return }
            a.swapAt(parent, child)
            parent = child
        }
    }
}
