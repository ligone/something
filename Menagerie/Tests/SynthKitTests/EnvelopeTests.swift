import SynthKit
import XCTest

final class EnvelopeTests: XCTestCase {
    private let sampleRate = 48_000.0

    func testReachesSustainThenReleasesToZeroWithinTheExpectedTimes() {
        var envelope = ADSREnvelope(attack: 0.01, decay: 0.1, sustain: 0.5, release: 0.2, sampleRate: sampleRate)
        envelope.gateOn()

        // Attack: full level after exactly the attack time.
        var samples = 0
        var previous: Float = 0
        while envelope.stage == .attack {
            let level = envelope.next()
            XCTAssertGreaterThanOrEqual(level, previous, "attack must rise monotonically")
            previous = level
            samples += 1
            XCTAssertLessThan(samples, 10_000)
        }
        XCTAssertEqual(Double(samples), 0.01 * sampleRate, accuracy: 2)
        XCTAssertEqual(envelope.level, 1)

        // Decay: reaches the sustain level no later than the decay time.
        samples = 0
        while envelope.stage == .decay {
            let level = envelope.next()
            XCTAssertLessThanOrEqual(level, previous, "decay must fall monotonically")
            previous = level
            samples += 1
            XCTAssertLessThan(samples, 10_000)
        }
        XCTAssertEqual(envelope.stage, .sustain)
        XCTAssertLessThanOrEqual(Double(samples), 0.1 * sampleRate + 1)
        XCTAssertGreaterThan(Double(samples), 0.05 * sampleRate, "an exponential decay should not be instantaneous")

        // Sustain: holds its level.
        for _ in 0 ..< 4_800 { _ = envelope.next() }
        XCTAssertEqual(envelope.level, 0.5, accuracy: 0.001)

        // Release: reaches exactly zero no later than the release time, then goes idle.
        envelope.gateOff()
        samples = 0
        previous = envelope.level
        while envelope.stage == .release {
            let level = envelope.next()
            XCTAssertLessThanOrEqual(level, previous, "release must fall monotonically")
            previous = level
            samples += 1
            XCTAssertLessThan(samples, 20_000)
        }
        XCTAssertEqual(envelope.stage, .idle)
        XCTAssertEqual(envelope.level, 0)
        XCTAssertLessThanOrEqual(Double(samples), 0.2 * sampleRate + 1)
        XCTAssertGreaterThan(Double(samples), 0.1 * sampleRate)
    }

    func testRetriggerDuringReleaseContinuesFromTheCurrentLevel() {
        var envelope = ADSREnvelope(attack: 0.005, decay: 0.05, sustain: 0.8, release: 0.5, sampleRate: sampleRate)
        envelope.gateOn()
        for _ in 0 ..< 4_800 { _ = envelope.next() }
        envelope.gateOff()
        for _ in 0 ..< 2_400 { _ = envelope.next() }
        let before = envelope.level
        XCTAssertGreaterThan(before, 0.1)
        envelope.gateOn()
        let after = envelope.next()
        XCTAssertGreaterThanOrEqual(after, before, "a retrigger must not drop to zero")
        XCTAssertLessThan(after - before, 0.01, "a retrigger must not jump")
    }

    func testChangingSustainWhileHeldGlidesWithoutJumping() {
        var envelope = ADSREnvelope(attack: 0.005, decay: 0.02, sustain: 0.2, release: 0.1, sampleRate: sampleRate)
        envelope.gateOn()
        for _ in 0 ..< 4_800 { _ = envelope.next() }
        XCTAssertEqual(envelope.stage, .sustain)
        envelope.configure(attack: 0.005, decay: 0.02, sustain: 0.9, release: 0.1, sampleRate: sampleRate)
        var previous = envelope.level
        var largestStep: Float = 0
        for _ in 0 ..< 4_800 {
            let level = envelope.next()
            largestStep = max(largestStep, abs(level - previous))
            previous = level
        }
        XCTAssertEqual(envelope.level, 0.9, accuracy: 0.01)
        XCTAssertLessThan(largestStep, 0.01)
    }

    func testMinimumTimesPreventInstantaneousJumps() {
        var envelope = ADSREnvelope(attack: 0, decay: 0, sustain: 0.5, release: 0, sampleRate: sampleRate)
        envelope.gateOn()
        let first = envelope.next()
        XCTAssertLessThan(first, 0.1, "even a zero attack takes about a millisecond")
    }
}
