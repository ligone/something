import SynthKit
import XCTest

final class OscillatorTests: XCTestCase {
    private let sampleRate = 48_000.0

    func testFrequencyIsCorrectForEveryPeriodicWaveform() {
        for waveform in [Waveform.sine, .triangle, .sawtooth, .pulse] {
            for frequency in [55.0, 440.0, 1_234.5, 3_520.0] {
                var oscillator = SynthOscillator(waveform: waveform)
                let samples = SignalAnalysis.render(&oscillator, frequency: frequency, sampleRate: sampleRate, count: Int(sampleRate))
                let crossings = SignalAnalysis.risingZeroCrossings(samples)
                XCTAssertEqual(Double(crossings), frequency, accuracy: 1.5, "\(waveform) at \(frequency) Hz: \(crossings) crossings in one second")
                let measured = SignalAnalysis.frequencyByZeroCrossings(samples, sampleRate: sampleRate)
                XCTAssertEqual(measured, frequency, accuracy: frequency * 0.0005, "\(waveform) at \(frequency) Hz")
            }
        }
    }

    func testSupersawFundamentalIsAtTheRequestedPitch() {
        var oscillator = SynthOscillator(waveform: .supersaw, spread: 0)
        let size = 16_384
        let frequency = 3_000.0 // exactly bin 1024 at 48 kHz
        let samples = SignalAnalysis.render(&oscillator, frequency: frequency, sampleRate: sampleRate, count: size)
        let spectrum = SignalAnalysis.powerSpectrum(samples)
        let strongest = spectrum.indices.dropFirst().max { spectrum[$0] < spectrum[$1] }!
        XCTAssertEqual(Double(strongest) * sampleRate / Double(size), frequency, accuracy: sampleRate / Double(size))
    }

    func testPolyBLEPSawStaysBounded() {
        var frequency = 20.0
        while frequency < 20_000 {
            var oscillator = SynthOscillator(waveform: .sawtooth)
            // A whole number of periods, so the mean measures DC rather than a partial ramp.
            let period = sampleRate / frequency
            let count = Int((period * max((8_192 / period).rounded(.down), 1)).rounded())
            let samples = SignalAnalysis.render(&oscillator, frequency: frequency, sampleRate: sampleRate, count: count)
            XCTAssertLessThanOrEqual(SignalAnalysis.peak(samples), 1.0001, "saw at \(frequency) Hz")
            let mean = samples.reduce(0, +) / Float(samples.count)
            XCTAssertEqual(mean, 0, accuracy: 0.05, "saw at \(frequency) Hz should have no DC")
            frequency *= 1.37
        }
    }

    func testOscillatorsStayBoundedWhileSweepingPitch() {
        for waveform in Waveform.allCases {
            var oscillator = SynthOscillator(waveform: waveform, pulseWidth: 0.1, spread: 1)
            var buffer = [Float](repeating: 0, count: 48_000)
            buffer.withUnsafeMutableBufferPointer { b in
                // Glide from 20 Hz to 20 kHz within a single second.
                let start = Float(20 / sampleRate)
                let step = (Float(20_000 / sampleRate) - start) / Float(b.count)
                oscillator.render(into: b.baseAddress!, count: b.count, increment: start, incrementStep: step)
            }
            XCTAssertTrue(buffer.allSatisfy(\.isFinite), "\(waveform)")
            XCTAssertLessThan(SignalAnalysis.peak(buffer), 3, "\(waveform)")
        }
    }

    func testPolyBLEPSuppressesAliasing() {
        // A naive sawtooth folds strong inharmonic partials back below Nyquist; PolyBLEP should
        // push that energy far down relative to the harmonics.
        let size = 16_384
        let frequency = 2_345.6
        var oscillator = SynthOscillator(waveform: .sawtooth)
        let blep = SignalAnalysis.render(&oscillator, frequency: frequency, sampleRate: sampleRate, count: size)
        var phase = 0.0
        let naive: [Float] = (0 ..< size).map { _ in
            let value = Float(2 * phase - 1)
            phase += frequency / sampleRate
            if phase >= 1 { phase -= 1 }
            return value
        }
        let blepAlias = aliasRatio(blep, frequency: frequency, size: size)
        let naiveAlias = aliasRatio(naive, frequency: frequency, size: size)
        let improvement = 10 * log10(naiveAlias / blepAlias)
        XCTAssertGreaterThan(improvement, 10, "PolyBLEP should cut aliasing by more than 10 dB (got \(improvement) dB)")
    }

    func testPulseWidthSetsTheDutyCycle() {
        for width in [0.25, 0.5, 0.75] {
            var oscillator = SynthOscillator(waveform: .pulse, pulseWidth: Float(width))
            let samples = SignalAnalysis.render(&oscillator, frequency: 100, sampleRate: sampleRate, count: 48_000)
            // With the DC offset removed, the pulse swings between 2 − 2w and −2w around zero.
            let midpoint = Float(1 - 2 * width)
            let high = samples.filter { $0 > midpoint }.count
            XCTAssertEqual(Double(high) / Double(samples.count), width, accuracy: 0.01)
            let mean = samples.reduce(0, +) / Float(samples.count)
            XCTAssertEqual(mean, 0, accuracy: 0.01, "the pulse should have no DC offset")
        }
    }

    func testNoiseIsBoundedAndCentered() {
        var oscillator = SynthOscillator(waveform: .noise)
        let samples = SignalAnalysis.render(&oscillator, frequency: 440, sampleRate: sampleRate, count: 48_000)
        XCTAssertLessThanOrEqual(SignalAnalysis.peak(samples), 1)
        XCTAssertEqual(Double(samples.reduce(0, +)) / Double(samples.count), 0, accuracy: 0.02)
        XCTAssertEqual(SignalAnalysis.rms(samples), 1 / 3.0.squareRoot(), accuracy: 0.02)
    }

    func testSupersawHasSawLikeLoudness() {
        var oscillator = SynthOscillator(waveform: .supersaw, spread: 0.5)
        let samples = SignalAnalysis.render(&oscillator, frequency: 220, sampleRate: sampleRate, count: 96_000)
        XCTAssertEqual(SignalAnalysis.rms(samples), 1 / 3.0.squareRoot(), accuracy: 0.15)
        XCTAssertLessThan(SignalAnalysis.peak(samples), 3)
    }

    /// Fraction of spectral power that is not near a true harmonic of `frequency`.
    private func aliasRatio(_ samples: [Float], frequency: Double, size: Int) -> Double {
        let spectrum = SignalAnalysis.powerSpectrum(samples)
        let binWidth = sampleRate / Double(size)
        var alias = 0.0
        var total = 0.0
        for (k, power) in spectrum.enumerated() where k > 2 {
            let f = Double(k) * binWidth
            let harmonic = (f / frequency).rounded()
            let distance = abs(f - harmonic * frequency) / binWidth
            total += power
            if harmonic < 1 || distance > 4 { alias += power }
        }
        return alias / total
    }
}
