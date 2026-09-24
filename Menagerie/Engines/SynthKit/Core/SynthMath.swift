import Foundation

/// Numeric helpers shared by the DSP code.
///
/// Everything here is allocation-free and cheap enough to call per sample on the audio thread.
enum SynthMath {
    /// Frequency in hertz of a (possibly fractional) MIDI note number, with A4 (note 69) at 440 Hz.
    @inline(__always)
    static func frequency(ofNote note: Double) -> Double {
        440 * exp2((note - 69) / 12)
    }

    /// A tanh-shaped rational saturator, `x·(27 + x²) / (27 + 9x²)`.
    ///
    /// It is exact at zero, monotonic, and reaches ±1 with zero slope at ±3, so clamping the input
    /// there keeps it smooth everywhere. It costs a single division, far less than `tanh`.
    @inline(__always)
    static func softSaturate(_ x: Float) -> Float {
        let c = min(max(x, -3), 3)
        let c2 = c * c
        return c * (27 + c2) / (27 + 9 * c2)
    }

    /// Clamps `value` into `range`, mapping NaN and infinities to `fallback`.
    @inline(__always)
    static func sanitize(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// One-pole smoothing coefficient: a step input is ~63 % of the way there after `time` seconds
    /// when the smoother is updated `rate` times per second.
    static func smoothingCoefficient(time: Double, rate: Double) -> Float {
        guard time > 0, rate > 0 else { return 1 }
        return Float(1 - exp(-1 / (time * rate)))
    }

    /// Coefficient of a one-pole low-pass (`y += a·(x − y)`) with the given cutoff.
    static func onePoleCoefficient(cutoff: Double, sampleRate: Double) -> Float {
        let fc = min(max(cutoff, 1), sampleRate * 0.49)
        return Float(1 - exp(-2 * Double.pi * fc / sampleRate))
    }

    /// Equal-power stereo gains for a pan position in −1 (left) … +1 (right).
    static func panGains(_ position: Float) -> (left: Float, right: Float) {
        let p = min(max(position, -1), 1)
        let angle = Double(p + 1) * Double.pi / 4
        return (Float(cos(angle)), Float(sin(angle)))
    }
}

/// A small, fast, deterministic pseudo-random generator (SplitMix64).
///
/// The generative sequencer must play exactly the same music for the same seed on every platform
/// and Swift version, so SynthKit carries its own generator and its own bounded-integer mapping
/// instead of relying on the standard library's unspecified `random(in:using:)` algorithms.
public struct SynthRandom: Sendable, Equatable {
    private var state: UInt64

    /// Creates a generator; equal seeds produce identical sequences.
    public init(seed: UInt64) {
        state = seed
    }

    /// Returns the next 64 random bits.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniformly distributed integer in `0 ..< bound` (Lemire's multiply-shift; bias below 2⁻³²).
    public mutating func nextInt(below bound: Int) -> Int {
        guard bound > 1 else { return 0 }
        let r = next() >> 32
        return Int((r &* UInt64(bound)) >> 32)
    }

    /// A uniformly distributed value in `0 ..< 1`.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Returns `true` with the given probability.
    public mutating func chance(_ probability: Double) -> Bool {
        nextUnit() < probability
    }
}
