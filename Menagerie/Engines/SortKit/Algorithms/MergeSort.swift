/// Top-down merge sort with an auxiliary buffer.
enum MergeSort {
    static func sort(_ a: inout SortRecorder) {
        var buffer: [Int] = []
        buffer.reserveCapacity(a.count)
        sort(&a, lo: 0, hi: a.count, buffer: &buffer)
    }

    /// Sorts `lo..<hi`.
    private static func sort(_ a: inout SortRecorder, lo: Int, hi: Int, buffer: inout [Int]) {
        guard hi - lo > 1 else { return }
        let mid = lo + (hi - lo) / 2
        sort(&a, lo: lo, hi: mid, buffer: &buffer)
        sort(&a, lo: mid, hi: hi, buffer: &buffer)
        merge(&a, lo: lo, mid: mid, hi: hi, buffer: &buffer)
    }

    /// Merges the sorted runs `lo..<mid` and `mid..<hi`.
    ///
    /// The merge reads both runs in place and collects the output in the
    /// buffer, so the array doesn't change until the copy-back. That keeps
    /// every recorded comparison pointing at the elements really compared.
    private static func merge(_ a: inout SortRecorder, lo: Int, mid: Int, hi: Int, buffer: inout [Int]) {
        a.mark(.range(lo..<hi))
        buffer.removeAll(keepingCapacity: true)

        var i = lo
        var j = mid
        while i < mid && j < hi {
            // Take from the right run only when it is strictly smaller, so
            // equal elements keep their order: that's what makes it stable.
            if a.less(j, i) {
                buffer.append(a.peek(j))
                j += 1
            } else {
                buffer.append(a.peek(i))
                i += 1
            }
        }
        while i < mid {
            buffer.append(a.read(i))
            i += 1
        }
        // Whatever is left of the right run already sits in its final place,
        // right after the buffer's contents.

        for (offset, value) in buffer.enumerated() {
            a.write(value, at: lo + offset)
        }
    }
}
