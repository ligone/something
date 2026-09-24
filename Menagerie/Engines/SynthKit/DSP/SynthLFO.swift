import Foundation

/// A low-frequency oscillator for vibrato and filter sweeps.
///
/// The engine advances it at control rate (every 16 samples), which is ample for rates up to 20 Hz.
public struct SynthLFO: Sendable {
    /// Waveform of the modulation.
    public var shape: LFOShape
    /// Phase in `0 ..< 1`.
    public private(set) var phase: Double

    /// Creates an LFO starting at `phase`.
    public init(shape: LFOShape = .sine, phase: Double = 0) {
        self.shape = shape
        self.phase = phase - phase.rounded(.down)
    }

    /// Advances the phase by `seconds` at `rate` hertz.
    public mutating func advance(seconds: Double, rate: Double) {
        guard rate.isFinite, seconds.isFinite else { return }
        phase += seconds * rate
        phase -= phase.rounded(.down)
    }

    /// Restarts at phase 0.
    public mutating func reset() {
        phase = 0
    }

    /// The current value in −1 … 1. Both shapes start at 0 and rise, so they are interchangeable.
    public var value: Float {
        switch shape {
        case .sine:
            return Float(sin(2 * Double.pi * phase))
        case .triangle:
            let p = phase
            if p < 0.25 { return Float(4 * p) }
            if p < 0.75 { return Float(2 - 4 * p) }
            return Float(4 * p - 4)
        }
    }
}
