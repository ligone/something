import SynthKit
import XCTest

final class FilterTests: XCTestCase {
    private let sampleRate: Float = 48_000

    /// Filters a sine through a fixed filter and returns the output RMS after settling.
    private func response(frequency: Float, cutoff: Float, resonance: Float, tap: (SVFilterOutput) -> Float) -> Double {
        var filter = SVFilter()
        let g = SVFilter.gain(cutoff: cutoff, sampleRate: sampleRate)
        let k = SVFilter.damping(resonance: resonance)
        var output: [Float] = []
        output.reserveCapacity(48_000)
        for n in 0 ..< 48_000 {
            let x = sin(2 * Float.pi * frequency * Float(n) / sampleRate)
            output.append(tap(filter.process(x, g: g, k: k)))
        }
        return SignalAnalysis.rms(output[24_000...])
    }

    func testLowPassAttenuatesAboveCutoffFarMoreThanBelow() {
        let below = response(frequency: 250, cutoff: 1_000, resonance: 0) { $0.lowPass }
        let above = response(frequency: 4_000, cutoff: 1_000, resonance: 0) { $0.lowPass }
        XCTAssertGreaterThan(below, 0.6, "a sine two octaves below cutoff should pass nearly untouched")
        XCTAssertGreaterThan(below / above, 10, "12 dB/octave: two octaves up should be > 20 dB quieter")
    }

    func testMeasuredResponseMatchesTheAnalyticCurve() {
        let inputRMS = 1 / 2.0.squareRoot()
        for (mode, tap) in [(FilterMode.lowPass12, { (o: SVFilterOutput) in o.lowPass }),
                            (.bandPass, { $0.bandPass }),
                            (.highPass, { $0.highPass })] {
            for frequency in [200.0, 1_000.0, 3_000.0] {
                let measured = response(frequency: Float(frequency), cutoff: 1_000, resonance: 0.4, tap: tap) / inputRMS
                let expected = SVFilter.magnitude(at: frequency, cutoff: 1_000, resonance: 0.4, mode: mode, sampleRate: Double(sampleRate))
                XCTAssertEqual(measured, expected, accuracy: expected * 0.03 + 0.001, "\(mode) at \(frequency) Hz")
            }
        }
    }

    func testHighPassAndBandPassSelectTheRightBand() {
        let highBelow = response(frequency: 250, cutoff: 1_000, resonance: 0) { $0.highPass }
        let highAbove = response(frequency: 4_000, cutoff: 1_000, resonance: 0) { $0.highPass }
        XCTAssertGreaterThan(highAbove / highBelow, 10)

        let bandAt = response(frequency: 1_000, cutoff: 1_000, resonance: 0.5) { $0.bandPass }
        let bandOff = response(frequency: 8_000, cutoff: 1_000, resonance: 0.5) { $0.bandPass }
        XCTAssertGreaterThan(bandAt / bandOff, 5)
    }

    func testFourPoleModeIsSteeperThanTwoPole() {
        let twoPole = SVFilter.magnitude(at: 4_000, cutoff: 1_000, resonance: 0, mode: .lowPass12, sampleRate: 48_000)
        let fourPole = SVFilter.magnitude(at: 4_000, cutoff: 1_000, resonance: 0, mode: .lowPass24, sampleRate: 48_000)
        XCTAssertLessThan(20 * log10(twoPole), -20)
        XCTAssertLessThan(20 * log10(fourPole), -40)
        let passband = SVFilter.magnitude(at: 100, cutoff: 1_000, resonance: 0, mode: .lowPass24, sampleRate: 48_000)
        XCTAssertEqual(passband, 1, accuracy: 0.05)
    }

    func testResonanceBoostsTheCutoffFrequency() {
        let flat = response(frequency: 1_000, cutoff: 1_000, resonance: 0) { $0.lowPass }
        let resonant = response(frequency: 1_000, cutoff: 1_000, resonance: 0.8) { $0.lowPass }
        XCTAssertGreaterThan(resonant / flat, 8)
    }

    func testStaysStableUnderAudioRateModulationAtMaximumResonance() {
        var filter = SVFilter()
        var random = SynthRandom(seed: 7)
        let k = SVFilter.damping(resonance: 1)
        var peak: Float = 0
        for n in 0 ..< 96_000 {
            // Sweep the cutoff between 30 Hz and 18 kHz at 300 Hz: far faster than any envelope.
            let sweep = 0.5 + 0.5 * sin(2 * Float.pi * 300 * Float(n) / sampleRate)
            let cutoff = 30 * pow(600, sweep)
            let g = SVFilter.gain(cutoff: cutoff, sampleRate: sampleRate)
            let x = Float(random.nextUnit() * 2 - 1)
            let y = filter.process(x, g: g, k: k).lowPass
            filter.saturateResonance(limit: 3)
            XCTAssertTrue(y.isFinite)
            peak = max(peak, abs(y))
        }
        XCTAssertLessThan(peak, 20)
    }
}
