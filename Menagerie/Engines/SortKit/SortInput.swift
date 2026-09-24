/// Shapes of input data. Every generator returns values in `1...count`, so
/// they map directly onto bar heights, and the same seed always gives the
/// same array on every platform.
public enum SortInput: String, CaseIterable, Identifiable, Sendable {
    /// A uniformly random permutation of 1...n.
    case random
    /// 1...n in order, with a few nearby pairs swapped.
    case nearlySorted
    /// n down to 1.
    case reversed
    /// Six distinct values, repeated and shuffled.
    case fewUnique
    /// Four ascending ramps, each spanning the full range of values.
    case sawtooth

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .random: "Random"
        case .nearlySorted: "Nearly Sorted"
        case .reversed: "Reversed"
        case .fewUnique: "Few Unique"
        case .sawtooth: "Sawtooth"
        }
    }

    /// The number of distinct values in `fewUnique` inputs.
    public static let fewUniqueLevels = 6
    /// The number of ramps in `sawtooth` inputs.
    public static let sawtoothTeeth = 4

    /// Generates `count` values in `1...count`.
    public func generate(count: Int, seed: UInt64) -> [Int] {
        guard count > 0 else { return [] }
        var random = SortRandom(seed: seed)
        switch self {
        case .random:
            var values = Array(1...count)
            random.shuffle(&values)
            return values

        case .nearlySorted:
            var values = Array(1...count)
            guard count > 1 else { return values }
            let swaps = max(1, count / 16)
            let reach = max(2, count / 32)
            for _ in 0..<swaps {
                let i = random.next(below: count)
                let offset = 1 + random.next(below: reach)
                let j = i + offset < count ? i + offset : i - offset
                if j >= 0 {
                    values.swapAt(i, j)
                }
            }
            return values

        case .reversed:
            return Array((1...count).reversed())

        case .fewUnique:
            let levels = min(count, Self.fewUniqueLevels)
            // Equal-sized groups at evenly spaced heights, then shuffled.
            var values = (0..<count).map { index in
                let level = index * levels / count
                return (level + 1) * count / levels
            }
            random.shuffle(&values)
            return values

        case .sawtooth:
            // Deal 1...n round-robin into the teeth, then lay the teeth end
            // to end: each one climbs from near the bottom to near the top.
            let teeth = min(count, Self.sawtoothTeeth)
            var values: [Int] = []
            values.reserveCapacity(count)
            for tooth in 0..<teeth {
                values.append(contentsOf: stride(from: tooth + 1, through: count, by: teeth))
            }
            return values
        }
    }
}

/// SplitMix64: a tiny, fast, seedable random number generator. Its output,
/// and every generator built on it here, is identical on every platform.
public struct SortRandom: RandomNumberGenerator, Sendable {
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

    /// A value in `0..<bound`, using Lemire's multiply-shift reduction. The
    /// bias is at most bound / 2⁶⁴, far too small to matter here.
    public mutating func next(below bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let product = next().multipliedFullWidth(by: UInt64(bound))
        return Int(product.high)
    }

    /// Fisher–Yates shuffle, spelled out so the result doesn't depend on the
    /// standard library's implementation.
    public mutating func shuffle(_ values: inout [Int]) {
        guard values.count > 1 else { return }
        for i in stride(from: values.count - 1, to: 0, by: -1) {
            let j = next(below: i + 1)
            values.swapAt(i, j)
        }
    }
}
