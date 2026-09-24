import Foundation
import SynthKit
import XCTest

final class AnalysisTests: XCTestCase {
    func testFFTMatchesANaiveDFT() {
        var random = SynthRandom(seed: 42)
        for size in [2, 8, 64, 512] {
            let input = (0 ..< size).map { _ in Float(random.nextUnit() * 2 - 1) }
            var real = input
            var imag = (0 ..< size).map { _ in Float(random.nextUnit() * 2 - 1) }
            let imagInput = imag
            SynthFFT(size: size).forward(real: &real, imag: &imag)

            var errorEnergy = 0.0
            var signalEnergy = 0.0
            for k in 0 ..< size {
                var sumRe = 0.0
                var sumIm = 0.0
                for n in 0 ..< size {
                    let angle = -2 * Double.pi * Double(n * k) / Double(size)
                    let (re, im) = (Double(input[n]), Double(imagInput[n]))
                    sumRe += re * cos(angle) - im * sin(angle)
                    sumIm += re * sin(angle) + im * cos(angle)
                }
                errorEnergy += pow(sumRe - Double(real[k]), 2) + pow(sumIm - Double(imag[k]), 2)
                signalEnergy += sumRe * sumRe + sumIm * sumIm
            }
            XCTAssertLessThan((errorEnergy / signalEnergy).squareRoot(), 1e-5, "size \(size)")
        }
    }

    func testFFTPutsASineInItsBin() {
        let size = 1_024
        var real = (0 ..< size).map { Float(sin(2 * Double.pi * 37 * Double($0) / Double(size))) }
        var imag = [Float](repeating: 0, count: size)
        SynthFFT(size: size).forward(real: &real, imag: &imag)
        let magnitudes = (0 ..< size / 2).map { (real[$0] * real[$0] + imag[$0] * imag[$0]).squareRoot() }
        XCTAssertEqual(magnitudes.indices.max { magnitudes[$0] < magnitudes[$1] }, 37)
        XCTAssertEqual(magnitudes[37], Float(size) / 2, accuracy: 0.01 * Float(size))
    }

    func testSpectrumAnalyzerFindsAToneAtFullScale() {
        let sampleRate = 48_000.0
        let analyzer = SynthSpectrumAnalyzer(fftSize: 4_096, bandCount: 64, sampleRate: sampleRate)
        let tone = (0 ..< 4_096).map { Float(sin(2 * Double.pi * 1_000 * Double($0) / sampleRate)) }
        for _ in 0 ..< 30 { analyzer.analyze(tone, deltaTime: 1 / 60) }
        let loudest = analyzer.levels.indices.max { analyzer.levels[$0] < analyzer.levels[$1] }!
        let spacing = pow(analyzer.maximumFrequency / analyzer.minimumFrequency, 1 / Double(analyzer.bandCount))
        XCTAssertEqual(log(analyzer.frequency(ofBand: loudest) / 1_000) / log(spacing), 0, accuracy: 1)
        XCTAssertEqual(analyzer.levels[loudest], 1, accuracy: 0.03, "a full-scale sine reads 0 dB")
        XCTAssertGreaterThanOrEqual(analyzer.peaks[loudest], analyzer.levels[loudest])
        XCTAssertLessThan(analyzer.levels[0], 0.2, "30 Hz holds almost nothing")

        for _ in 0 ..< 120 { analyzer.decay(deltaTime: 1 / 60) }
        XCTAssertLessThan(analyzer.levels[loudest], 0.01, "levels fall back when the sound stops")
    }

    func testOscilloscopeTriggersOnARisingZeroCrossing() {
        let history = (0 ..< 4_000).map { Float(0.8 * sin(2 * Double.pi * Double($0) / 97.3 + 1.1)) }
        var output = [Float](repeating: 0, count: 1_000)
        let found = history.withUnsafeBufferPointer { h in
            output.withUnsafeMutableBufferPointer { SynthOscilloscope.trigger(history: h, into: $0) }
        }
        XCTAssertTrue(found)
        XCTAssertEqual(output[0], 0, accuracy: 1e-3)
        XCTAssertGreaterThan(output[5], 0)
        // One period later the trace is back at a rising zero crossing.
        XCTAssertEqual(output[97], 0, accuracy: 0.03)
    }

    func testOscilloscopeFallsBackToTheNewestSamplesWithoutATrigger() {
        let history = [Float](repeating: 0, count: 2_048)
        var output = [Float](repeating: 1, count: 512)
        let found = history.withUnsafeBufferPointer { h in
            output.withUnsafeMutableBufferPointer { SynthOscilloscope.trigger(history: h, into: $0) }
        }
        XCTAssertFalse(found)
        XCTAssertTrue(output.allSatisfy { $0 == 0 })
    }
}
