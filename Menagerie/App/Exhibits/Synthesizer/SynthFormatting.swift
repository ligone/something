import SwiftUI
import SynthKit

/// Colors of the synthesizer exhibit, built around the exhibit tint.
enum SynthPalette {
    static let accent = Exhibit.synthesizer.tint
    static let violet = Color(red: 0.56, green: 0.40, blue: 0.99)
    static let magenta = Color(red: 0.98, green: 0.34, blue: 0.74)
    static let stageTop = Color(red: 0.035, green: 0.05, blue: 0.10)
    static let stageBottom = Color(red: 0.012, green: 0.016, blue: 0.035)
    /// Cyan → violet → magenta, used from quiet (bottom) to loud (top).
    static let spectrum = Gradient(colors: [accent, violet, magenta])
}

/// Maps a positive parameter onto 0 … 1 logarithmically, so a slider spends equal travel on every
/// octave (or decade) instead of cramming the musical range into its first few pixels.
struct LogScale {
    let range: ClosedRange<Double>

    func position(of value: Double) -> Double {
        let low = range.lowerBound
        let high = range.upperBound
        let clamped = min(max(value, low), high)
        return log(clamped / low) / log(high / low)
    }

    func value(at position: Double) -> Double {
        let p = min(max(position, 0), 1)
        return range.lowerBound * pow(range.upperBound / range.lowerBound, p)
    }

    static let cutoff = LogScale(range: SynthPatch.Filter.cutoffRange)
    static let lfoRate = LogScale(range: SynthPatch.LFO.rateRange)
    static let delayTime = LogScale(range: SynthPatch.Effects.delayTimeRange)
    static let reverbDecay = LogScale(range: SynthPatch.Effects.reverbDecayRange)
}

/// Human-readable parameter values.
enum SynthFormat {
    static func frequency(_ hertz: Double) -> String {
        hertz >= 1_000 ? String(format: "%.1f kHz", hertz / 1_000) : String(format: "%.0f Hz", hertz)
    }

    static func rate(_ hertz: Double) -> String {
        hertz < 1 ? String(format: "%.2f Hz", hertz) : String(format: "%.1f Hz", hertz)
    }

    static func time(_ seconds: Double) -> String {
        seconds < 1 ? String(format: "%.0f ms", seconds * 1_000) : String(format: "%.2f s", seconds)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    static func cents(_ cents: Double) -> String {
        abs(cents) < 0.5 ? "0 ct" : String(format: "%+.0f ct", cents)
    }

    static func octaves(_ octaves: Double) -> String {
        abs(octaves) < 0.05 ? "0 oct" : String(format: "%+.1f oct", octaves)
    }

    static func tempo(_ bpm: Double) -> String {
        String(format: "%.0f BPM", bpm)
    }

    /// Oscillator balance as "70 : 30".
    static func balance(_ mix: Double) -> String {
        let second = Int((mix * 100).rounded())
        return "\(100 - second) : \(second)"
    }

    static func sampleRate(_ hertz: Double) -> String {
        guard hertz > 0 else { return "–" }
        let kilohertz = hertz / 1_000
        return kilohertz == kilohertz.rounded() ? "\(Int(kilohertz)) kHz" : String(format: "%.1f kHz", kilohertz)
    }

    static func load(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    /// "C4" for MIDI note 60.
    static func noteName(_ note: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[((note % 12) + 12) % 12] + "\(note / 12 - 1)"
    }
}
