import XCTest
import LifeKit

final class ForceKernelTests: XCTestCase {
    private let beta: Float = 0.3

    private func force(_ distance: Float, _ attraction: Float) -> Float {
        LifeRules.force(atDistance: distance, attraction: attraction, repulsionRadius: beta)
    }

    func testUniversalRepulsionFallsLinearlyToZeroAtBeta() {
        XCTAssertEqual(force(0, 1), -1, accuracy: 1e-6)
        XCTAssertEqual(force(beta / 2, 1), -0.5, accuracy: 1e-6)
        XCTAssertEqual(force(beta, 1), 0, accuracy: 1e-6)
        // Repulsion ignores the matrix entirely.
        XCTAssertEqual(force(0.1, -1), force(0.1, 1), accuracy: 1e-6)
        XCTAssertEqual(force(0.1, 0), force(0.1, 1), accuracy: 1e-6)
    }

    func testSpeciesForceIsATrianglePeakingHalfwayOut() {
        let peak = (1 + beta) / 2
        XCTAssertEqual(force(peak, 0.8), 0.8, accuracy: 1e-6)
        XCTAssertEqual(force(peak, -0.6), -0.6, accuracy: 1e-6)
        XCTAssertEqual(force((beta + peak) / 2, 1), 0.5, accuracy: 1e-5)
        XCTAssertEqual(force((peak + 1) / 2, 1), 0.5, accuracy: 1e-5)
        XCTAssertEqual(force(0.999_99, 1), 0, accuracy: 1e-4)
    }

    func testNoForceAtOrBeyondTheInteractionRadius() {
        XCTAssertEqual(force(1, 1), 0)
        XCTAssertEqual(force(1.5, -1), 0)
    }

    func testForceIsContinuous() {
        var previous = force(0, 0.7)
        var distance: Float = 0.001
        while distance < 1.2 {
            let current = force(distance, 0.7)
            XCTAssertLessThan(abs(current - previous), 0.02, "jump at r = \(distance)")
            previous = current
            distance += 0.001
        }
    }

    func testFrictionHalvesVelocityEveryHalfLife() {
        let rules = LifeRules(frictionHalfLife: 0.05)
        XCTAssertEqual(rules.frictionFactor(overStep: 0.05), 0.5, accuracy: 1e-6)
        XCTAssertEqual(rules.frictionFactor(overStep: 0.1), 0.25, accuracy: 1e-6)
        XCTAssertEqual(rules.frictionFactor(overStep: 0), 1, accuracy: 1e-6)
    }
}

final class LifeRandomTests: XCTestCase {
    func testSameSeedGivesTheSameSequence() {
        var first = LifeRandom(seed: 42)
        var second = LifeRandom(seed: 42)
        for _ in 0..<1_000 {
            XCTAssertEqual(first.next(), second.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var first = LifeRandom(seed: 1)
        var second = LifeRandom(seed: 2)
        let a = (0..<16).map { _ in first.next() }
        let b = (0..<16).map { _ in second.next() }
        XCTAssertNotEqual(a, b)
    }

    func testUnitValuesAreUniformInTheHalfOpenInterval() {
        var random = LifeRandom(seed: 7)
        var buckets = [Int](repeating: 0, count: 10)
        let samples = 100_000
        for _ in 0..<samples {
            let value = random.nextUnit()
            XCTAssertTrue(value >= 0 && value < 1)
            buckets[Int(value * 10)] += 1
        }
        for count in buckets {
            XCTAssertEqual(Double(count) / Double(samples), 0.1, accuracy: 0.01)
        }
    }

    func testBoundedIntegersStayInRange() {
        var random = LifeRandom(seed: 8)
        var seen = Set<Int>()
        for _ in 0..<10_000 {
            let value = random.nextInt(below: 7)
            XCTAssertTrue((0..<7).contains(value))
            seen.insert(value)
        }
        XCTAssertEqual(seen.count, 7)
    }
}
