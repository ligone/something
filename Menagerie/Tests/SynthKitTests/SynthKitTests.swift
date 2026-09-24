import SynthKit
import XCTest

/// Shared signal-analysis helpers for the SynthKit test suite.
enum SignalAnalysis {
    /// Root-mean-square level.
    static func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for x in samples { sum += Double(x) * Double(x) }
        return (sum / Double(samples.count)).squareRoot()
    }

    static func rms(_ samples: [Float]) -> Double {
        rms(samples[...])
    }

    /// Largest absolute sample.
    static func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// Number of upward zero crossings.
    static func risingZeroCrossings(_ samples: [Float]) -> Int {
        var count = 0
        for i in 1 ..< samples.count where samples[i - 1] < 0 && samples[i] >= 0 {
            count += 1
        }
        return count
    }

    /// Frequency estimated from rising zero crossings, refined to sub-sample precision by linear
    /// interpolation between the first and last crossing.
    static func frequencyByZeroCrossings(_ samples: [Float], sampleRate: Double) -> Double {
        var first = -1.0
        var last = -1.0
        var crossings = 0
        for i in 1 ..< samples.count where samples[i - 1] < 0 && samples[i] >= 0 {
            let a = Double(samples[i - 1])
            let b = Double(samples[i])
            let position = Double(i - 1) + (-a / (b - a))
            if first < 0 { first = position }
            last = position
            crossings += 1
        }
        guard crossings > 1 else { return 0 }
        return Double(crossings - 1) / (last - first) * sampleRate
    }

    /// Renders `seconds` of stereo audio from `engine`, calling it in `blockSize` chunks.
    static func render(_ engine: SynthEngine, seconds: Double, blockSize: Int = 512) -> (left: [Float], right: [Float]) {
        let total = Int(seconds * engine.sampleRate)
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                var offset = 0
                while offset < total {
                    let n = min(blockSize, total - offset)
                    engine.render(frameCount: n, left: l.baseAddress! + offset, right: r.baseAddress! + offset)
                    offset += n
                }
            }
        }
        return (left, right)
    }

    /// Renders one block and returns its left channel.
    static func renderMono(_ engine: SynthEngine, frames: Int) -> [Float] {
        render(engine, seconds: Double(frames) / engine.sampleRate).left
    }

    /// Renders an oscillator directly.
    static func render(_ oscillator: inout SynthOscillator, frequency: Double, sampleRate: Double, count: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        let increment = Float(frequency / sampleRate)
        samples.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < count {
                let n = min(64, count - offset)
                oscillator.render(into: buffer.baseAddress! + offset, count: n, increment: increment)
                offset += n
            }
        }
        return samples
    }

    /// Power spectrum (|X|²) of a Hann-windowed signal of power-of-two length.
    static func powerSpectrum(_ samples: [Float]) -> [Double] {
        let n = samples.count
        let fft = SynthFFT(size: n)
        var real = samples.enumerated().map { i, x in
            x * Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n)))
        }
        var imag = [Float](repeating: 0, count: n)
        fft.forward(real: &real, imag: &imag)
        return (0 ... n / 2).map { Double(real[$0]) * Double(real[$0]) + Double(imag[$0]) * Double(imag[$0]) }
    }
}

/// A simple, dry patch for measurements: one oscillator, filter wide open, no modulation, no
/// effects, full sustain.
func testPatch(_ waveform: Waveform = .sine) -> SynthPatch {
    SynthPatch(
        osc1: .init(waveform: waveform),
        osc2: .init(waveform: .sine),
        oscMix: 0,
        subLevel: 0,
        filter: .init(mode: .lowPass12, cutoff: 20_000, resonance: 0, envelopeAmount: 0, keyTracking: 0, velocityAmount: 0, drive: 0),
        ampEnvelope: .init(attack: 0.005, decay: 0.1, sustain: 1, release: 0.05),
        filterEnvelope: .init(attack: 0.005, decay: 0.1, sustain: 1, release: 0.05),
        lfo: .init(shape: .sine, rate: 1, pitchDepth: 0, cutoffDepth: 0),
        velocitySensitivity: 0,
        stereoSpread: 0,
        level: 1,
        effects: .init(chorusMix: 0, delayTime: 0.3, delayFeedback: 0, delayMix: 0, reverbDecay: 1, reverbDamping: 0.5, reverbMix: 0)
    )
}
