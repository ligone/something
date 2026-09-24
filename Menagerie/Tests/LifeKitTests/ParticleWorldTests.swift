import Foundation
import XCTest
import LifeKit

final class ParticleWorldTests: XCTestCase {
    // MARK: - Neighbor search

    func testGridNeighborSearchMatchesBruteForce() {
        // A non-square domain whose sides are not multiples of the radius,
        // plus particles pinned to the seams and corners.
        let rules = LifeRules(interactionRadius: 0.137)
        let world = makeWorld(particles: 1_500, domain: TorusDomain(width: 1.7, height: 1.0), rules: rules, seed: 4)
        let edges: [(Float, Float)] = [
            (0, 0), (1.699, 0.999), (0.001, 0.5), (1.69, 0.5), (0.85, 0.0005), (0.85, 0.9995), (1.6999, 0.0001),
        ]
        for (index, point) in edges.enumerated() {
            world.setParticle(index, x: point.0, y: point.1)
        }
        assertNeighborsMatchBruteForce(in: world)
    }

    func testNeighborSearchOnAMinimalThreeByThreeGrid() {
        // Exactly three cells per side: every cell is a neighbor of every other.
        let world = makeWorld(particles: 400, domain: TorusDomain(width: 0.33, height: 0.31),
                              rules: LifeRules(interactionRadius: 0.1), seed: 12)
        assertNeighborsMatchBruteForce(in: world)
    }

    func testNeighborSearchInADomainTooSmallForAGrid() {
        // Fewer than three cells fit, so the world falls back to comparing all pairs.
        let world = makeWorld(particles: 300, domain: TorusDomain(width: 0.25, height: 0.4),
                              rules: LifeRules(interactionRadius: 0.1), seed: 13)
        assertNeighborsMatchBruteForce(in: world)
    }

    private func assertNeighborsMatchBruteForce(in world: ParticleWorld, file: StaticString = #filePath, line: UInt = #line) {
        var checkedPairs = 0
        for index in 0..<world.particleCount {
            let found = Set(world.neighbors(of: index))
            let expected = bruteForceNeighbors(of: index, in: world)
            XCTAssertTrue(expected.definite.isSubset(of: found),
                          "particle \(index) is missing \(expected.definite.subtracting(found))", file: file, line: line)
            XCTAssertTrue(found.isSubset(of: expected.possible),
                          "particle \(index) has extra \(found.subtracting(expected.possible))", file: file, line: line)
            checkedPairs += found.count
        }
        XCTAssertGreaterThan(checkedPairs, world.particleCount,
                             "the test should exercise real neighborhoods", file: file, line: line)
    }

    // MARK: - Forces

    func testGridForcesMatchBruteForce() {
        // From rest, one step leaves every velocity equal to acceleration × dt,
        // which exposes the kernel's force sums directly.
        let dt: Float = 1e-3
        let rules = LifeRules(interactionRadius: 0.12, maximumSpeed: 1e6)
        for (domain, seed) in [(TorusDomain(width: 1.3, height: 0.9), UInt64(1)), (TorusDomain(width: 0.3, height: 0.3), 2)] {
            let world = makeWorld(particles: 1_200, domain: domain, rules: rules, seed: seed)
            let expected = bruteForceAccelerations(in: world)
            world.step(by: dt)
            var largest: Float = 0
            for index in 0..<world.particleCount {
                let velocity = world.velocity(of: index)
                let (ax, ay) = (velocity.x / dt, velocity.y / dt)
                let tolerance = 1e-3 * (1 + abs(expected[index].x) + abs(expected[index].y))
                XCTAssertEqual(ax, expected[index].x, accuracy: tolerance, "particle \(index)")
                XCTAssertEqual(ay, expected[index].y, accuracy: tolerance, "particle \(index)")
                largest = max(largest, abs(expected[index].x), abs(expected[index].y))
            }
            XCTAssertGreaterThan(largest, 1, "the configuration should produce substantial forces")
        }
    }

    func testAsymmetricAttractionMakesOneSpeciesChaseAnother() {
        // Red is drawn to blue, blue flees red: both end up moving the same way.
        let matrix = SpeciesMatrix(rows: [[0, 1], [-1, 0]])
        let rules = LifeRules(interactionRadius: 0.1)
        let world = ParticleWorld(particleCount: 2, matrix: matrix, rules: rules, seed: 0)
        world.setParticle(0, x: 0.5, y: 0.5, species: 0)
        world.setParticle(1, x: 0.565, y: 0.5, species: 1)
        world.step(by: 1.0 / 60.0)
        let chaser = world.velocity(of: 0)
        let fleer = world.velocity(of: 1)
        XCTAssertGreaterThan(chaser.x, 0)
        XCTAssertGreaterThan(fleer.x, 0)
        XCTAssertEqual(chaser.y, 0, accuracy: 1e-6)
        XCTAssertEqual(fleer.y, 0, accuracy: 1e-6)
        XCTAssertEqual(chaser.x, fleer.x, accuracy: 1e-5, "equal and opposite matrix entries give equal speeds")
    }

    func testCloseParticlesRepelRegardlessOfTheMatrix() {
        let world = ParticleWorld(particleCount: 2, matrix: SpeciesMatrix(speciesCount: 1, repeating: 1), seed: 0)
        world.setParticle(0, x: 0.5, y: 0.5)
        world.setParticle(1, x: 0.51, y: 0.5)
        world.step(by: 1.0 / 60.0)
        XCTAssertLessThan(world.velocity(of: 0).x, 0)
        XCTAssertGreaterThan(world.velocity(of: 1).x, 0)
    }

    // MARK: - Integration

    func testParticlesStayInBounds() {
        // Violent settings: strong forces, little friction, a fast cap, a
        // pointer, and long steps that carry particles across the seams.
        let rules = LifeRules(interactionRadius: 0.1, forceStrength: 40, frictionHalfLife: 0.5, maximumSpeed: 20)
        let world = makeWorld(particles: 2_000, domain: TorusDomain(width: 1.3, height: 0.8), rules: rules, seed: 6)
        world.pointer = ParticlePointer(x: 0.6, y: 0.4, radius: 0.3, strength: -40, velocityX: 5, velocityY: -3)
        for step in 0..<150 {
            world.step(by: step.isMultiple(of: 3) ? 0.05 : 1.0 / 60.0)
            XCTAssertTrue(allParticlesInBounds(world), "escaped at step \(step)")
        }
        world.resizeDomain(to: TorusDomain(width: 0.5, height: 1.7))
        XCTAssertTrue(allParticlesInBounds(world))
        world.setParticleCount(3_000)
        world.step(by: 1.0 / 60.0)
        XCTAssertTrue(allParticlesInBounds(world))
    }

    func testParticlesStayInBoundsInATinyDomain() {
        let rules = LifeRules(interactionRadius: 0.1, forceStrength: 30, maximumSpeed: 20)
        let world = makeWorld(particles: 200, domain: TorusDomain(width: 0.2, height: 0.15), rules: rules, seed: 8)
        for _ in 0..<100 {
            world.step(by: 0.04)
            XCTAssertTrue(allParticlesInBounds(world))
        }
    }

    func testSpeedsDecayExactlyAsTheHalfLifePredicts() {
        // Particles far apart never interact, so friction alone acts on them.
        let rules = LifeRules(interactionRadius: 0.05, frictionHalfLife: 0.1)
        let world = ParticleWorld(particleCount: 16, matrix: SpeciesMatrix(speciesCount: 3), rules: rules, seed: 0)
        for index in 0..<16 {
            let angle = Float(index) * 0.4
            world.setParticle(index, x: 0.125 + Float(index % 4) * 0.25, y: 0.125 + Float(index / 4) * 0.25,
                              velocityX: 0.2 * cos(angle), velocityY: 0.2 * sin(angle))
        }
        let dt: Float = 1.0 / 60.0
        let steps = 30
        for _ in 0..<steps {
            world.step(by: dt)
        }
        let expected = 0.2 * rules.frictionFactor(overStep: dt * Float(steps))
        for index in 0..<16 {
            let velocity = world.velocity(of: index)
            let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
            XCTAssertEqual(speed, expected, accuracy: 1e-5)
        }
    }

    func testZeroMatrixWorldComesToRest() {
        // With no species forces, only short-range repulsion and friction are
        // left; a dense, stirred-up world must settle down.
        let world = ParticleWorld(particleCount: 1_500, matrix: SpeciesMatrix(speciesCount: 4), seed: 3)
        var random = LifeRandom(seed: 99)
        for index in 0..<world.particleCount {
            let position = world.position(of: index)
            world.setParticle(index, x: position.x, y: position.y,
                              velocityX: random.nextFloat(from: -1, to: 1), velocityY: random.nextFloat(from: -1, to: 1))
        }
        let initial = world.meanSpeed
        var previous = initial
        for second in 1...4 {
            world.advance(by: 0.5)
            let current = world.meanSpeed
            XCTAssertLessThan(current, previous, "speed rose during second \(second)")
            previous = current
        }
        XCTAssertLessThan(previous, initial * 0.01)
    }

    // MARK: - Determinism

    func testSteppingIsDeterministicForASeed() {
        func run(seed: UInt64) -> WorldSnapshot {
            let world = makeWorld(particles: 2_500, seed: seed)
            for step in 0..<90 {
                if step == 30 { world.pointer = ParticlePointer(x: 0.8, y: 0.5, velocityX: 1) }
                if step == 60 { world.pointer = nil }
                world.step(by: 1.0 / 60.0)
            }
            return WorldSnapshot(world)
        }
        XCTAssertEqual(run(seed: 77), run(seed: 77))
        XCTAssertNotEqual(run(seed: 77), run(seed: 78))
    }

    func testConcurrencyDoesNotChangeTheResult() {
        let parallel = makeWorld(particles: 4_000, seed: 5)
        let serial = makeWorld(particles: 4_000, seed: 5)
        serial.allowsConcurrency = false
        for _ in 0..<40 {
            parallel.step(by: 1.0 / 60.0)
            serial.step(by: 1.0 / 60.0)
        }
        XCTAssertEqual(WorldSnapshot(parallel), WorldSnapshot(serial))
    }

    func testScatterIsReproducible() {
        let first = makeWorld(particles: 500, seed: 31)
        let second = makeWorld(particles: 500, seed: 31)
        first.scatter()
        second.scatter()
        XCTAssertEqual(WorldSnapshot(first), WorldSnapshot(second))
        XCTAssertEqual(first.meanSpeed, 0)
    }

    // MARK: - Editing the world

    func testChangingTheParticleCountKeepsSpeciesBalanced() {
        let world = makeWorld(particles: 1_000, species: 4, seed: 2)
        XCTAssertEqual(world.speciesPopulations, [250, 250, 250, 250])
        world.setParticleCount(1_800)
        XCTAssertEqual(world.particleCount, 1_800)
        XCTAssertEqual(world.speciesPopulations.reduce(0, +), 1_800)
        XCTAssertLessThanOrEqual(world.speciesPopulations.max()! - world.speciesPopulations.min()!, 2)
        XCTAssertTrue(allParticlesInBounds(world))

        let before = Set(WorldSnapshot(world).x)
        world.setParticleCount(600)
        XCTAssertEqual(world.particleCount, 600)
        XCTAssertTrue(Set(WorldSnapshot(world).x).isSubset(of: before), "shrinking keeps existing particles")
        world.setParticleCount(0)
        world.step(by: 1.0 / 60.0)
        XCTAssertEqual(world.meanSpeed, 0)
    }

    func testChangingTheSpeciesCountRedistributesSpecies() {
        let world = makeWorld(particles: 999, species: 3, seed: 2)
        var random = LifeRandom(seed: 1)
        world.matrix = world.matrix.resized(to: 7, using: &random)
        XCTAssertEqual(world.speciesCount, 7)
        let populations = world.speciesPopulations
        XCTAssertEqual(populations.count, 7)
        XCTAssertLessThanOrEqual(populations.max()! - populations.min()!, 1)
        world.matrix = world.matrix.resized(to: 2, using: &random)
        XCTAssertTrue((0..<world.particleCount).allSatisfy { world.species(of: $0) < 2 })
    }

    func testResizingTheDomainStretchesPositions() {
        let world = makeWorld(particles: 50, domain: TorusDomain(width: 1, height: 1), seed: 9)
        let before = WorldSnapshot(world)
        world.resizeDomain(to: TorusDomain(width: 2, height: 0.5))
        let after = WorldSnapshot(world)
        for index in 0..<50 {
            XCTAssertEqual(after.x[index], before.x[index] * 2, accuracy: 1e-5)
            XCTAssertEqual(after.y[index], before.y[index] * 0.5, accuracy: 1e-5)
        }
    }

    func testAdvanceSplitsTimeIntoEqualSteps() {
        let world = makeWorld(particles: 100, seed: 1)
        XCTAssertEqual(world.advance(by: 0.05, maximumStep: 0.02), 3)
        XCTAssertEqual(world.stepCount, 3)
        XCTAssertEqual(world.elapsedTime, 0.05, accuracy: 1e-6)
        XCTAssertEqual(world.advance(by: 0), 0)
    }

    // MARK: - Pointer

    func testPointerAttractsAndRepelsWithinItsRadius() {
        func velocityAfterOneStep(strength: Float, particleX: Float) -> Float {
            let world = ParticleWorld(particleCount: 1, matrix: SpeciesMatrix(speciesCount: 1), seed: 0)
            world.setParticle(0, x: particleX, y: 0.5)
            world.pointer = ParticlePointer(x: 0.5, y: 0.5, radius: 0.2, strength: strength, stirring: 0)
            world.step(by: 1.0 / 60.0)
            return world.velocity(of: 0).x
        }
        XCTAssertGreaterThan(velocityAfterOneStep(strength: 8, particleX: 0.4), 0, "pulled right, toward the pointer")
        XCTAssertLessThan(velocityAfterOneStep(strength: -8, particleX: 0.4), 0, "pushed left, away from it")
        XCTAssertEqual(velocityAfterOneStep(strength: 8, particleX: 0.1), 0, "out of reach")
        // Across the seam: a pointer near the right edge reaches a particle near the left edge.
        let world = ParticleWorld(particleCount: 1, matrix: SpeciesMatrix(speciesCount: 1), seed: 0)
        world.setParticle(0, x: 0.02, y: 0.5)
        world.pointer = ParticlePointer(x: 0.95, y: 0.5, radius: 0.2, strength: 8, stirring: 0)
        world.step(by: 1.0 / 60.0)
        XCTAssertLessThan(world.velocity(of: 0).x, 0)
    }

    func testPointerStirringDragsParticlesAlong() {
        let world = ParticleWorld(particleCount: 1, matrix: SpeciesMatrix(speciesCount: 1), seed: 0)
        world.setParticle(0, x: 0.5, y: 0.5)
        world.pointer = ParticlePointer(x: 0.5, y: 0.5, radius: 0.2, strength: 0, velocityX: 0, velocityY: 1, stirring: 10)
        for _ in 0..<10 {
            world.step(by: 1.0 / 60.0)
        }
        XCTAssertGreaterThan(world.velocity(of: 0).y, 0.1)
    }
}
