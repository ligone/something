/// Sorts that repair the array by exchanging out-of-order pairs.
enum ExchangeSorts {
    /// Bubble sort that remembers where each pass last swapped: everything
    /// after that point is already in its final place, and a pass without
    /// swaps ends the sort (n − 1 comparisons on sorted input).
    static func bubble(_ a: inout SortRecorder) {
        var end = a.count
        while end > 1 {
            a.mark(.range(0..<end))
            var lastSwap = 0
            for i in 1..<end {
                if a.less(i, i - 1) {
                    a.swapAt(i - 1, i)
                    lastSwap = i
                }
            }
            end = lastSwap
        }
    }

    /// Bubble sort that alternates direction, shrinking the unsorted window
    /// from both ends.
    static func cocktailShaker(_ a: inout SortRecorder) {
        var lo = 0
        var hi = a.count - 1
        while lo < hi {
            // Forward: carry the largest value up to `hi`.
            a.mark(.range(lo..<(hi + 1)))
            var lastSwap = lo
            for i in lo..<hi {
                if a.less(i + 1, i) {
                    a.swapAt(i, i + 1)
                    lastSwap = i
                }
            }
            hi = lastSwap
            guard lo < hi else { break }

            // Backward: carry the smallest value down to `lo`.
            a.mark(.range(lo..<(hi + 1)))
            lastSwap = hi
            for i in stride(from: hi, to: lo, by: -1) {
                if a.less(i, i - 1) {
                    a.swapAt(i - 1, i)
                    lastSwap = i
                }
            }
            lo = lastSwap
        }
    }

    /// The garden gnome: step forward while the pair behind you is in order,
    /// otherwise swap it and step back.
    static func gnome(_ a: inout SortRecorder) {
        var position = 1
        while position < a.count {
            if position == 0 || !a.less(position, position - 1) {
                position += 1
            } else {
                a.swapAt(position - 1, position)
                position -= 1
            }
        }
    }

    /// Bubble sort over a gap that shrinks by a factor of 1.3 each pass. It
    /// finishes with ordinary bubble passes (gap 1) until one makes no swaps.
    static func comb(_ a: inout SortRecorder) {
        let n = a.count
        guard n > 1 else { return }
        var gap = n
        var swapped = true
        while gap > 1 || swapped {
            gap = nextCombGap(after: gap)
            a.mark(.gap(gap))
            swapped = false
            for i in 0..<(n - gap) {
                if a.less(i + gap, i) {
                    a.swapAt(i, i + gap)
                    swapped = true
                }
            }
        }
        a.mark(.gap(nil))
    }

    /// Divides by 1.3 using integers, with the "Combsort11" refinement: gaps
    /// of 9 and 10 become 11, which avoids a slow tail of small gaps.
    static func nextCombGap(after gap: Int) -> Int {
        let next = gap * 10 / 13
        if next == 9 || next == 10 {
            return 11
        }
        return max(1, next)
    }
}
