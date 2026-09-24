import Foundation
import SynthKit

/// One display frame of visualizer data.
struct SynthVisualFrame {
    /// Oscilloscope window starting at a rising zero crossing, −1 … 1.
    var scope: [Float]
    /// Spectrum band levels and peak-hold markers, 0 … 1.
    var levels: [Float]
    var peaks: [Float]
    /// Light on each MIDI note's key, 0 … 1 (fades out after release).
    var keyGlow: [Float]
    /// Automatic gain that keeps quiet waveforms readable on the oscilloscope.
    var scopeGain: Float
    /// Smoothed loudness, 0 … 1, for the ambient glow.
    var energy: Float
}

/// Pulls fresh audio from the engine once per display frame and turns it into drawable data:
/// a triggered oscilloscope window, smoothed log-frequency spectrum bands with peak hold, and a
/// glow level per key.
///
/// It is deliberately not observable. Views read it inside a `TimelineView(.animation)`, so
/// the 60 fps data flow never invalidates the rest of the SwiftUI hierarchy.
@MainActor
final class SynthVisualizerFeed {
    static let scopeLength = 1_024
    static let historyLength = 4_096
    static let bandCount = 72
    /// Frequency span of the spectrum display.
    static let minimumFrequency = 30.0
    static let maximumFrequency = 16_000.0

    private weak var engine: SynthEngine?
    private var analyzer: SynthSpectrumAnalyzer?
    private var history = [Float](repeating: 0, count: historyLength)
    private var scope = [Float](repeating: 0, count: scopeLength)
    private var keyGlow = [Float](repeating: 0, count: 128)
    private var scopeGain: Float = 1
    private var energy: Float = 0
    private var lastTime: TimeInterval = 0
    private var current: SynthVisualFrame

    init() {
        let silence = [Float](repeating: 0, count: Self.bandCount)
        current = SynthVisualFrame(
            scope: [Float](repeating: 0, count: Self.scopeLength),
            levels: silence,
            peaks: silence,
            keyGlow: [Float](repeating: 0, count: 128),
            scopeGain: 1,
            energy: 0
        )
    }

    /// Connects to a running engine, or disconnects with `nil`.
    func attach(engine: SynthEngine?) {
        self.engine = engine
        if let engine, analyzer?.sampleRate != engine.sampleRate {
            analyzer = SynthSpectrumAnalyzer(
                fftSize: Self.historyLength,
                bandCount: Self.bandCount,
                sampleRate: engine.sampleRate,
                minimumFrequency: Self.minimumFrequency,
                maximumFrequency: Self.maximumFrequency
            )
        }
        if engine == nil {
            analyzer?.reset()
            for i in scope.indices { scope[i] = 0 }
            for i in keyGlow.indices { keyGlow[i] = 0 }
            energy = 0
            lastTime = 0
        }
    }

    /// Advances the visuals to `date` and returns the frame to draw.
    ///
    /// Several views may ask during the same display frame; only the first call does work.
    func frame(at date: Date, localNotes: SynthNoteSet) -> SynthVisualFrame {
        let now = date.timeIntervalSinceReferenceDate
        let elapsed = now - lastTime
        if lastTime != 0 && elapsed < 0.004 { return current }
        let deltaTime = lastTime == 0 ? 1.0 / 60 : min(max(elapsed, 0), 0.1)
        lastTime = now
        advance(deltaTime: deltaTime, localNotes: localNotes)
        return current
    }

    private func advance(deltaTime: Double, localNotes: SynthNoteSet) {
        var status = SynthStatus()
        if let engine {
            engine.copyRecentOutput(into: &history)
            history.withUnsafeBufferPointer { recent in
                scope.withUnsafeMutableBufferPointer { window in
                    _ = SynthOscilloscope.trigger(history: recent, into: window)
                }
            }
            analyzer?.analyze(history, deltaTime: deltaTime)
            status = engine.status
        } else {
            analyzer?.decay(deltaTime: deltaTime)
        }

        // Auto-gain: quiet sounds are magnified (up to 6×) so their shape stays visible.
        var peak: Float = 0
        for sample in scope { peak = max(peak, abs(sample)) }
        let dt = Float(deltaTime)
        let targetGain = min(0.85 / max(peak, 0.08), 6)
        scopeGain += (targetGain - scopeGain) * (1 - exp(-dt / 0.3))
        energy += (min(peak * 2.5, 1) - energy) * (1 - exp(-dt / 0.15))

        // Keys light up instantly and fade out; release tails keep a faint glow.
        let fade = 1 - exp(-dt / 0.14)
        for note in 0 ..< 128 {
            let target: Float
            if status.heldNotes.contains(note) || localNotes.contains(note) {
                target = 1
            } else if status.soundingNotes.contains(note) {
                target = 0.3
            } else {
                target = 0
            }
            let glow = keyGlow[note]
            keyGlow[note] = target > glow ? target : glow + (target - glow) * fade
        }

        current = SynthVisualFrame(
            scope: scope,
            levels: analyzer?.levels ?? current.levels,
            peaks: analyzer?.peaks ?? current.peaks,
            keyGlow: keyGlow,
            scopeGain: scopeGain,
            energy: energy
        )
    }
}
