import Foundation

/// The three simultaneous outputs of `SVFilter`.
public struct SVFilterOutput: Sendable {
    public var lowPass: Float
    public var bandPass: Float
    public var highPass: Float
}

/// A topology-preserving-transform (TPT) state-variable filter, after Vadim Zavalishin and
/// Andrew Simper.
///
/// The analog SVF's two integrators are discretized with the trapezoidal rule, and the zero-delay
/// feedback loop this creates is solved exactly instead of being broken with a unit delay. The
/// digital filter therefore keeps the analog response (with bilinear pre-warping of the cutoff)
/// and stays stable while its cutoff is swept at audio rate, which is what envelopes and LFOs do.
public struct SVFilter: Sendable {
    /// State of the first (band-pass) integrator.
    public private(set) var ic1eq: Float = 0
    /// State of the second (low-pass) integrator.
    public private(set) var ic2eq: Float = 0

    public init() {}

    /// Clears the filter's memory.
    public mutating func reset() {
        ic1eq = 0
        ic2eq = 0
    }

    /// The pre-warped integrator gain `g = tan(π·fc/fs)`, with the cutoff clamped to 10 Hz … 0.49·fs.
    @inline(__always)
    public static func gain(cutoff: Float, sampleRate: Float) -> Float {
        let fc = min(max(cutoff, 10), sampleRate * 0.49)
        return tan(Float.pi * fc / sampleRate)
    }

    /// Damping `k = 1/Q` for a normalized resonance: 0 gives Q = 0.5 (no peak), 1 gives Q = 25.
    public static func damping(resonance: Float) -> Float {
        let r = min(max(resonance, 0), 1)
        return 2 * exp(-r * log(Float(50)))
    }

    /// Damping of the first, fixed stage of the four-pole low-pass: a Butterworth section
    /// (Q ≈ 0.54) so the resonance of the second stage alone shapes the peak.
    public static var fourPoleFirstStageDamping: Float { 1.847_759 }

    /// Filters one sample.
    ///
    /// - Parameters:
    ///   - g: Integrator gain from `gain(cutoff:sampleRate:)`.
    ///   - k: Damping from `damping(resonance:)`.
    @inline(__always)
    public mutating func process(_ input: Float, g: Float, k: Float) -> SVFilterOutput {
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2
        let v3 = input - ic2eq
        let v1 = a1 * ic1eq + a2 * v3
        let v2 = ic2eq + a2 * ic1eq + a3 * v3
        ic1eq = 2 * v1 - ic1eq
        ic2eq = 2 * v2 - ic2eq
        return SVFilterOutput(lowPass: v2, bandPass: v1, highPass: input - k * v1 - v2)
    }

    /// Softly limits the band-pass integrator so high resonance saturates like an analog filter
    /// instead of ringing without bound. It only ever removes energy, so it cannot destabilize the
    /// filter, and it is nearly transparent at normal levels.
    @inline(__always)
    public mutating func saturateResonance(limit: Float) {
        ic1eq = limit * SynthMath.softSaturate(ic1eq / limit)
    }

    /// Magnitude response of the filter as the voice uses it, for drawing response curves.
    ///
    /// Evaluates the analog prototype at the pre-warped frequency, which is exactly the response
    /// of the bilinear-transformed digital filter.
    public static func magnitude(at frequency: Double, cutoff: Double, resonance: Double, mode: FilterMode, sampleRate: Double) -> Double {
        let nyquistGuard = sampleRate * 0.49
        let f = min(max(frequency, 1), nyquistGuard)
        let fc = min(max(cutoff, 10), nyquistGuard)
        let w = tan(Double.pi * f / sampleRate) / tan(Double.pi * fc / sampleRate)
        let k = Double(damping(resonance: Float(resonance)))

        func section(_ k: Double) -> (lp: Double, bp: Double, hp: Double) {
            // H(s) = {1, s, s²} / (s² + k·s + 1) at s = jw.
            let re = 1 - w * w
            let im = k * w
            let denominator = (re * re + im * im).squareRoot()
            return (1 / denominator, w / denominator, w * w / denominator)
        }

        let main = section(k)
        switch mode {
        case .lowPass12: return main.lp
        case .lowPass24: return main.lp * section(Double(fourPoleFirstStageDamping)).lp
        case .bandPass: return main.bp
        case .highPass: return main.hp
        }
    }
}
