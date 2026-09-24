/// A fixed-size cache of search results, keyed by position.
///
/// Many move orders reach the same position, and iterative deepening searches
/// the same positions again one ply deeper. The table remembers what each
/// search learned (a score bound, the depth behind it and the best move) so
/// repeats cost a single lookup.
///
/// Each slot is one `UInt64`: the low 32 bits of the position key in the high
/// half, and the packed result in the low half (see `C4Searcher`). A position
/// hashes to a bucket, the key modulo a prime number of buckets. Since that
/// prime and 2³² are coprime and their product exceeds 2⁴⁹, the Chinese
/// remainder theorem says the bucket and the stored 32 bits together pin down
/// the 49-bit key exactly, so a lookup never mistakes one position for
/// another.
///
/// Each bucket has two slots. The first keeps the deepest result of the
/// current search, the second takes whatever comes last. Deep results are
/// expensive to recompute, so they should survive the flood of shallow
/// ones, but a slot that only ever kept deep results would fill up with
/// stale ones. Each search therefore gets a new generation number, and a
/// result from an older generation can always be replaced.
final class C4TranspositionTable {
    /// Number of buckets, a prime.
    let bucketCount: Int
    /// The slots, two per bucket. Zero marks an empty slot.
    let slots: UnsafeMutablePointer<UInt64>
    /// The current search's generation, 1–15. It wraps around; an entry that
    /// is 16 generations old merely survives a little longer than it should.
    private(set) var generation: UInt32 = 0

    /// A table with at least `minimumSize` slots of 8 bytes each. At least
    /// 2¹⁷ buckets are used, since fewer would break the uniqueness argument
    /// above.
    init(minimumSize: Int) {
        bucketCount = Self.prime(atLeast: max(minimumSize / 2, (1 << 17) + 1))
        slots = UnsafeMutablePointer<UInt64>.allocate(capacity: 2 * bucketCount)
        slots.initialize(repeating: 0, count: 2 * bucketCount)
    }

    deinit {
        slots.deallocate()
    }

    /// Forgets every stored result.
    func clear() {
        slots.update(repeating: 0, count: 2 * bucketCount)
        generation = 0
    }

    /// Starts a new generation for a new search and returns it.
    func beginSearch() -> UInt32 {
        generation = generation % 15 + 1
        return generation
    }

    static func prime(atLeast n: Int) -> Int {
        var candidate = n | 1
        while !isPrime(candidate) {
            candidate += 2
        }
        return candidate
    }

    static func isPrime(_ n: Int) -> Bool {
        if n < 2 { return false }
        if n % 2 == 0 { return n == 2 }
        var divisor = 3
        while divisor * divisor <= n {
            if n % divisor == 0 { return false }
            divisor += 2
        }
        return true
    }
}
