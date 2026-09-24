/// A small, fast, seedable random number generator (xoshiro256**).
///
/// The standard library's `SystemRandomNumberGenerator` cannot be seeded, so
/// LifeKit uses this generator wherever results must be reproducible: the same
/// seed yields the same sequence on every platform and every run. The unit
/// conversions below are written out explicitly, rather than relying on
/// `Float.random(in:using:)`, so that seeded worlds stay bit-for-bit identical
/// across Swift versions too.
public struct LifeRandom: RandomNumberGenerator, Sendable {
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    /// Creates a generator whose whole future sequence is determined by `seed`.
    public init(seed: UInt64) {
        // Expand the 64-bit seed into 256 bits of state with SplitMix64, as the
        // xoshiro authors recommend. SplitMix64 never produces an all-zero state.
        var mixer = seed
        func splitMix() -> UInt64 {
            mixer &+= 0x9E37_79B9_7F4A_7C15
            var z = mixer
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        s0 = splitMix()
        s1 = splitMix()
        s2 = splitMix()
        s3 = splitMix()
    }

    /// Returns the next 64 random bits.
    public mutating func next() -> UInt64 {
        let result = rotateLeft(s1 &* 5, by: 7) &* 9
        let shifted = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= shifted
        s3 = rotateLeft(s3, by: 45)
        return result
    }

    /// A uniformly distributed value in `0 ..< 1`, with 24 bits of precision.
    public mutating func nextUnit() -> Float {
        Float(next() >> 40) * 0x1p-24
    }

    /// A uniformly distributed value in `lower ..< upper`.
    public mutating func nextFloat(from lower: Float, to upper: Float) -> Float {
        lower + (upper - lower) * nextUnit()
    }

    /// A uniformly distributed integer in `0 ..< bound`. `bound` must be positive.
    public mutating func nextInt(below bound: Int) -> Int {
        precondition(bound > 0, "nextInt(below:) needs a positive bound")
        return Self.index(below: bound, from: next())
    }

    /// Maps 64 random bits to `0 ..< bound` with a multiply-shift, which avoids
    /// the bias and the division of a plain modulo.
    static func index(below bound: Int, from bits: UInt64) -> Int {
        Int(UInt64(bound).multipliedFullWidth(by: bits).high)
    }

    private func rotateLeft(_ value: UInt64, by amount: UInt64) -> UInt64 {
        (value << amount) | (value >> (64 - amount))
    }
}

/// A uniform value in `-1 ..< 1` drawn from any generator, with the same
/// explicit bit conversion as ``LifeRandom/nextUnit()``.
func signedUnit<G: RandomNumberGenerator>(using generator: inout G) -> Float {
    Float(generator.next() >> 40) * 0x1p-23 - 1
}
