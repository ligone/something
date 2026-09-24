import Foundation

/// Polynomial band-limited step (PolyBLEP) and ramp (PolyBLAMP) corrections.
///
/// A naive sawtooth jumps instantaneously, which puts energy into every harmonic up to infinity;
/// everything above Nyquist folds back as inharmonic aliasing. PolyBLEP replaces the two samples
/// around each jump with a polynomial approximation of a band-limited step (the integral of a
/// two-sample triangular kernel), which removes most of that energy for a few multiplies.
/// PolyBLAMP is its integral and rounds off the corners of a triangle wave the same way.
///
/// Both functions take the oscillator phase `t` in `0 ..< 1` measured from the discontinuity and
/// the per-sample phase increment `dt`, and return zero away from it.
public enum PolyBLEP {
    /// Correction for a step of height 2 (−1 → +1) at phase 0.
    /// Add it for a rising step, subtract it for a falling one.
    @inline(__always)
    public static func step(_ t: Float, _ dt: Float) -> Float {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    /// Correction for a change of slope of 1 per sample at phase 0 (scale it by the slope change).
    @inline(__always)
    public static func ramp(_ t: Float, _ dt: Float) -> Float {
        if t < dt {
            let x = 1 - t / dt
            return x * x * x * (1 / 6)
        }
        if t > 1 - dt {
            let x = (t - 1) / dt + 1
            return x * x * x * (1 / 6)
        }
        return 0
    }
}

/// A band-limited audio oscillator.
///
/// `render(into:count:increment:incrementStep:)` produces a block of samples while the phase
/// increment (frequency ÷ sample rate) glides linearly, so pitch modulation computed at control
/// rate reaches the waveform without zipper noise. Rendering never allocates.
public struct SynthOscillator: Sendable {
    /// The waveform to generate.
    public var waveform: Waveform
    /// Duty cycle of `.pulse`, clamped to 0.02 … 0.98.
    public var pulseWidth: Float
    /// Detune spread of `.supersaw`, 0 … 1.
    public var spread: Float

    /// Phase of the (center) waveform in `0 ..< 1`.
    public private(set) var phase: Float = 0

    private var sawPhases = SIMD8<Float>(repeating: 0)
    private var sawRatios = SIMD8<Float>(repeating: 1)
    private var sawGains = SIMD8<Float>(repeating: 0)
    private var cachedSpread: Float = -1
    private var randomState: UInt32

    /// Relative frequency offsets of the seven supersaw partials at full spread, as measured on
    /// the JP-8000 by Adam Szabo ("How to Emulate the Super Saw", 2010). Lane 7 is unused.
    /// (Computed rather than stored, so nothing lazily initialized runs on the audio thread.)
    private static var supersawOffsets: SIMD8<Float> {
        SIMD8<Float>(-0.110_023_13, -0.062_884_39, -0.019_523_56, 0, 0.019_912_21, 0.062_165_38, 0.107_452_42, 0)
    }

    /// Creates an oscillator. `seed` decorrelates the noise and supersaw phases of different voices.
    public init(waveform: Waveform = .sawtooth, pulseWidth: Float = 0.5, spread: Float = 0.4, seed: UInt32 = 0x2545_F491) {
        self.waveform = waveform
        self.pulseWidth = pulseWidth
        self.spread = spread
        randomState = seed == 0 ? 0x2545_F491 : seed
        scatterSupersawPhases()
    }

    /// Restarts the waveform at `phase` and scatters the supersaw partials to fresh random phases,
    /// as the free-running oscillators of the original do.
    public mutating func reset(phase: Float = 0) {
        self.phase = phase - phase.rounded(.down)
        scatterSupersawPhases()
    }

    /// Generates one sample. Convenient for tests; `render` is much faster for blocks.
    public mutating func nextSample(increment: Float) -> Float {
        var sample: Float = 0
        render(into: &sample, count: 1, increment: increment)
        return sample
    }

    /// Writes `count` samples to `output`.
    ///
    /// - Parameters:
    ///   - increment: Phase increment (frequency ÷ sample rate) of the first sample.
    ///   - incrementStep: Amount added to the increment after every sample.
    public mutating func render(into output: UnsafeMutablePointer<Float>, count: Int, increment: Float, incrementStep: Float = 0) {
        guard count > 0 else { return }
        let start = Self.clampIncrement(increment)
        let end = Self.clampIncrement(increment + incrementStep * Float(count))
        let step = (end - start) / Float(count)

        switch waveform {
        case .sine: renderSine(output, count, start, step)
        case .triangle: renderTriangle(output, count, start, step)
        case .sawtooth: renderSaw(output, count, start, step)
        case .pulse: renderPulse(output, count, start, step)
        case .supersaw: renderSupersaw(output, count, start, step)
        case .noise: renderNoise(output, count)
        }
    }

    // MARK: - Waveforms

    private mutating func renderSine(_ output: UnsafeMutablePointer<Float>, _ count: Int, _ increment: Float, _ step: Float) {
        var p = phase
        var dt = increment
        let twoPi = 2 * Float.pi
        for i in 0 ..< count {
            output[i] = sin(twoPi * p)
            p += dt
            if p >= 1 { p -= 1 }
            dt += step
        }
        phase = p
    }

    private mutating func renderTriangle(_ output: UnsafeMutablePointer<Float>, _ count: Int, _ increment: Float, _ step: Float) {
        var p = phase
        var dt = increment
        for i in 0 ..< count {
            var y: Float = p < 0.5 ? 4 * p - 1 : 3 - 4 * p
            // The slope flips by ±8·dt per sample at the trough (phase 0) and the peak (phase ½).
            let corner = 8 * dt
            var q = p + 0.5
            if q >= 1 { q -= 1 }
            y += corner * (PolyBLEP.ramp(p, dt) - PolyBLEP.ramp(q, dt))
            output[i] = y
            p += dt
            if p >= 1 { p -= 1 }
            dt += step
        }
        phase = p
    }

    private mutating func renderSaw(_ output: UnsafeMutablePointer<Float>, _ count: Int, _ increment: Float, _ step: Float) {
        var p = phase
        var dt = increment
        for i in 0 ..< count {
            output[i] = (p + p - 1) - PolyBLEP.step(p, dt)
            p += dt
            if p >= 1 { p -= 1 }
            dt += step
        }
        phase = p
    }

    private mutating func renderPulse(_ output: UnsafeMutablePointer<Float>, _ count: Int, _ increment: Float, _ step: Float) {
        let width = min(max(pulseWidth, 0.02), 0.98)
        // Removing the DC offset of an asymmetric pulse keeps pulse-width modulation from thumping.
        let dc = 2 * width - 1
        var p = phase
        var dt = increment
        for i in 0 ..< count {
            var y: Float = p < width ? 1 : -1
            var q = p - width
            if q < 0 { q += 1 }
            y += PolyBLEP.step(p, dt) - PolyBLEP.step(q, dt)
            output[i] = y - dc
            p += dt
            if p >= 1 { p -= 1 }
            dt += step
        }
        phase = p
    }

    private mutating func renderSupersaw(_ output: UnsafeMutablePointer<Float>, _ count: Int, _ increment: Float, _ step: Float) {
        updateSupersawShape()
        var p = sawPhases
        var dt = sawRatios * increment
        let dtStep = sawRatios * step
        let gains = sawGains
        let zero = SIMD8<Float>(repeating: 0)
        for i in 0 ..< count {
            // Seven PolyBLEP sawtooths at once, one per SIMD lane.
            let x1 = p / dt
            let x2 = (p - 1) / dt
            var residual = zero
            residual.replace(with: x2 * x2 + x2 + x2 + 1, where: p .> 1 - dt)
            residual.replace(with: x1 + x1 - x1 * x1 - 1, where: p .< dt)
            output[i] = ((p + p - 1 - residual) * gains).sum()
            p += dt
            p.replace(with: p - 1, where: p .>= 1)
            dt += dtStep
        }
        sawPhases = p
        phase = p[3]
    }

    private mutating func renderNoise(_ output: UnsafeMutablePointer<Float>, _ count: Int) {
        var s = randomState
        for i in 0 ..< count {
            s ^= s << 13
            s ^= s >> 17
            s ^= s << 5
            output[i] = Float(Int32(bitPattern: s)) * (1 / 2_147_483_648)
        }
        randomState = s
    }

    // MARK: - Helpers

    /// Keeps the increment strictly positive (the BLEP divides by it) and below Nyquist.
    @inline(__always)
    static func clampIncrement(_ increment: Float) -> Float {
        guard increment.isFinite else { return 1e-6 }
        return min(max(increment, 1e-6), 0.45)
    }

    /// Recomputes the partial ratios and gains when `spread` changes.
    ///
    /// The mix law is Szabo's fit of the JP-8000: the center saw fades as the side saws rise.
    /// Gains are normalized so the incoherent sum has the same RMS as a single sawtooth.
    private mutating func updateSupersawShape() {
        guard spread != cachedSpread else { return }
        cachedSpread = spread
        let s = min(max(spread, 0), 1)
        let amount = s * s * 0.85 + s * 0.15
        sawRatios = 1 + Self.supersawOffsets * amount
        let side = -0.737_64 * s * s + 1.2841 * s + 0.044_372
        let center = -0.553_66 * s + 0.997_85
        let norm = 1 / (center * center + 6 * side * side).squareRoot()
        sawGains = SIMD8<Float>(side, side, side, center, side, side, side, 0) * norm
    }

    private mutating func scatterSupersawPhases() {
        var s = randomState
        var phases = SIMD8<Float>(repeating: 0)
        for lane in 0 ..< 8 {
            s ^= s << 13
            s ^= s >> 17
            s ^= s << 5
            phases[lane] = Float(s >> 8) * (1 / 16_777_216)
        }
        randomState = s
        sawPhases = phases
    }
}
