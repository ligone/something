import XCTest
import LifeKit

final class LifePresetTests: XCTestCase {
    func testPresetsAreWellFormed() {
        XCTAssertGreaterThanOrEqual(LifePreset.all.count, 4)
        XCTAssertEqual(Set(LifePreset.all.map(\.name)).count, LifePreset.all.count, "names must be unique")
        for preset in LifePreset.all {
            XCTAssertTrue((2...8).contains(preset.matrix.speciesCount), preset.name)
            XCTAssertTrue(preset.matrix.values.allSatisfy { $0 >= -1 && $0 <= 1 }, preset.name)
            XCTAssertFalse(preset.summary.isEmpty, preset.name)
            XCTAssertEqual(LifePreset.named(preset.name), preset)
        }
        XCTAssertNil(LifePreset.named("No Such Preset"))
    }

    func testEveryPresetSelfOrganizes() {
        // Starting from uniform noise, each preset must gather its particles
        // into structures within a few simulated seconds.
        let domain = TorusDomain(aspectRatio: 1.2, area: 0.75)
        for preset in LifePreset.all {
            let world = ParticleWorld(particleCount: 1_500, matrix: preset.matrix, rules: preset.rules,
                                      domain: domain, seed: 21)
            XCTAssertLessThan(indexOfDispersion(world), 1.5, "\(preset.name) should start as uniform noise")
            world.advance(by: 4)
            XCTAssertGreaterThan(indexOfDispersion(world), 4, "\(preset.name) stayed diffuse")
        }
    }

    /// The variance-to-mean ratio of particle counts on a grid of half-radius
    /// cells: about 1 for a uniform (Poisson) scatter, and far above 1 once
    /// particles clump together and leave empty space between them.
    private func indexOfDispersion(_ world: ParticleWorld) -> Double {
        let cell = world.rules.interactionRadius / 2
        let columns = Int(world.domain.width / cell)
        let rows = Int(world.domain.height / cell)
        var counts = [Double](repeating: 0, count: columns * rows)
        for index in 0..<world.particleCount {
            let position = world.position(of: index)
            let column = min(Int(position.x / world.domain.width * Float(columns)), columns - 1)
            let row = min(Int(position.y / world.domain.height * Float(rows)), rows - 1)
            counts[row * columns + column] += 1
        }
        let mean = counts.reduce(0, +) / Double(counts.count)
        let variance = counts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(counts.count)
        return variance / mean
    }
}
