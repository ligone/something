/// A small, fast, seedable random number generator: SplitMix64 by Steele,
/// Lea and Flood, which passes BigCrush.
///
/// Every MazeKit generator draws from it through ``uniform(below:)`` and
/// ``shuffle(_:)``. Those are implemented here rather than with the standard
/// library's `random(in:using:)`, whose algorithm may change between
/// toolchains, so a seed carves the same maze on every platform.
public struct MazeRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniformly distributed integer in `0..<bound`, drawn without modulo
    /// bias using Lemire's multiply-and-reject method.
    public mutating func uniform(below bound: Int) -> Int {
        precondition(bound > 0, "uniform(below:) needs a positive bound")
        let range = UInt64(bound)
        var product = next().multipliedFullWidth(by: range)
        if product.low < range {
            let threshold = (0 &- range) % range
            while product.low < threshold {
                product = next().multipliedFullWidth(by: range)
            }
        }
        return Int(product.high)
    }

    /// A uniformly distributed `Double` in `0..<1` with 53 random bits.
    public mutating func unitInterval() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Shuffles the array in place with the Fisher–Yates algorithm.
    public mutating func shuffle<Element>(_ array: inout [Element]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = uniform(below: i + 1)
            if i != j { array.swapAt(i, j) }
        }
    }

    /// Derives an independent generator. MazeKit gives every phase of
    /// generation its own stream, so changing one option, such as the amount
    /// of mud, leaves the other phases untouched.
    func fork(_ salt: UInt64) -> MazeRandom {
        var mixer = MazeRandom(seed: state ^ salt)
        return MazeRandom(seed: mixer.next())
    }
}
