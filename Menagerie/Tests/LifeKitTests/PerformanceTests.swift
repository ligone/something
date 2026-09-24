import Dispatch
import XCTest
import LifeKit

final class PerformanceTests: XCTestCase {
    /// A smoke test, not a benchmark: stepping 4,000 clustered particles must
    /// stay far inside a frame budget even on a slow, shared CI machine. On an
    /// M-series Mac a step takes well under a millisecond.
    func testStepWithFourThousandParticlesIsFast() {
        let world = ParticleWorld(
            particleCount: 4_000,
            matrix: LifePreset.pondLife.matrix,
            rules: LifePreset.pondLife.rules,
            domain: TorusDomain(aspectRatio: 1.4, area: 2),
            seed: 1
        )
        // Let clusters form first: clumped particles have many more neighbors
        // than a uniform scatter, which is the realistic worst case.
        world.advance(by: 2)

        let steps = 30
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<steps {
            world.step(by: 1.0 / 60.0)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        let perStep = elapsed / Double(steps)
        XCTAssertLessThan(perStep, 0.05, "a step took \(perStep * 1000) ms")
    }
}
