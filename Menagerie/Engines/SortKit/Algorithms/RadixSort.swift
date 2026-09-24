/// Least-significant-digit radix sort in base 4.
enum RadixSort {
    /// Bits per digit. Base 4 takes more passes than base 256 would, which is
    /// exactly what makes it fun to watch.
    static let digitBits = 2
    static let base = 1 << digitBits

    /// Each pass reads the whole array to count how many elements have each
    /// digit, then writes the elements back grouped by that digit. Within a
    /// bucket they keep their order, so after the pass over the most
    /// significant digit the array is sorted.
    ///
    /// Keys are offset by the smallest key first, so negative numbers work
    /// and small ranges need few passes.
    static func leastSignificantDigitFirst(_ a: inout SortRecorder) {
        let n = a.count
        guard n > 1 else { return }

        // The key range decides the number of passes. This scan is
        // bookkeeping rather than sorting work, so it isn't recorded.
        var minKey = a.key(at: 0)
        var maxKey = minKey
        for i in 1..<n {
            let key = a.key(at: i)
            minKey = min(minKey, key)
            maxKey = max(maxKey, key)
        }
        // Wrapping arithmetic reinterpreted as unsigned: exact even for a
        // range as wide as Int.min...Int.max.
        let span = UInt(bitPattern: maxKey &- minKey)
        var digitCount = 0
        var remaining = span
        while remaining > 0 {
            digitCount += 1
            remaining >>= UInt(digitBits)
        }

        let mask = UInt(base - 1)
        var snapshot = [Int](repeating: 0, count: n)
        for digit in 0..<digitCount {
            a.mark(.digit(digit))
            let shift = UInt(digit * digitBits)
            func bucket(of value: Int) -> Int {
                Int((UInt(bitPattern: a.key(of: value) &- minKey) >> shift) & mask)
            }

            var bucketStarts = [Int](repeating: 0, count: base)
            for i in 0..<n {
                let value = a.read(i)
                snapshot[i] = value
                bucketStarts[bucket(of: value)] += 1
            }
            // Turn the counts into each bucket's first index.
            var total = 0
            for b in 0..<base {
                let count = bucketStarts[b]
                bucketStarts[b] = total
                total += count
            }
            for value in snapshot {
                let b = bucket(of: value)
                a.write(value, at: bucketStarts[b])
                bucketStarts[b] += 1
            }
        }
        a.mark(.digit(nil))
    }
}
