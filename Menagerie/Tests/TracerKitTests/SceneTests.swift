import Foundation
import TracerKit
import XCTest

final class SceneTests: XCTestCase {
    func testEveryPresetRendersAVisibleImage() {
        for preset in TracerScenePreset.allCases {
            let scene = preset.makeScene()
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertFalse(preset.subtitle.isEmpty)
            XCTAssertGreaterThan(scene.camera.focusDistance, 0)
            XCTAssertGreaterThan(scene.maxBounces, 0)

            let world = TracerWorld(scene: scene)
            let renderer = TracerRenderer(world: world, camera: scene.camera, width: 32, height: 20,
                                          settings: TracerRenderSettings(maxBounces: scene.maxBounces))
            renderer.renderPass()
            renderer.renderPass()
            let linear = renderer.snapshotLinear()
            XCTAssertTrue(linear.allSatisfy { $0.isFinite && $0 >= 0 }, "\(preset.title) produced invalid radiance")
            let mean = linear.reduce(0, +) / Float(linear.count)
            XCTAssertGreaterThan(mean, 0.02, "\(preset.title) renders almost black")
        }
    }

    func testPresetLightingSetups() {
        XCTAssertEqual(TracerWorld(scene: TracerScenePreset.cornellBox.makeScene()).lightCount, 1)
        XCTAssertEqual(TracerWorld(scene: TracerScenePreset.studio.makeScene()).lightCount, 5,
                       "Softbox, two rim lights, a fill card and a scrim")
        let marbles = TracerScenePreset.marbles.makeScene()
        XCTAssertNotNil(marbles.sky.sun, "The outdoor scene is lit by a sun")
        XCTAssertEqual(TracerWorld(scene: marbles).lightCount, 0)
    }

    func testMarblesIsDeterministicAndPopulated() {
        let scene = TracerScenePreset.marbles.makeScene()
        XCTAssertEqual(scene, TracerScenePreset.marbles.makeScene(), "The random layout is seeded")
        XCTAssertGreaterThan(scene.objects.count, 150)
        XCTAssertGreaterThan(TracerWorld(scene: scene).bvhNodeCount, 100)
    }

    /// The BVH must find exactly what testing every object would find.
    func testBVHAgreesWithBruteForce() {
        let scene = TracerScenePreset.marbles.makeScene()
        let world = TracerWorld(scene: scene)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }

        var hits = 0
        for _ in 0..<3000 {
            let origin = SIMD3<Float>(random() * 26 - 13, random() * 3 + 0.05, random() * 26 - 13)
            let direction = SIMD3<Float>(random() * 2 - 1, random() * 1.2 - 0.8, random() * 2 - 1)
            let ray = TracerRay(origin: origin, direction: direction)

            var nearest: (distance: Float, index: Int)?
            for (index, object) in scene.objects.enumerated() {
                if let hit = object.shape.intersect(ray), hit.distance < (nearest?.distance ?? .infinity) {
                    nearest = (hit.distance, index)
                }
            }
            let hit = world.intersect(ray)
            XCTAssertEqual(hit == nil, nearest == nil, "BVH and brute force disagree about hitting anything")
            guard let hit, let nearest else { continue }
            hits += 1
            XCTAssertEqual(hit.distance, nearest.distance, accuracy: 1e-4 * max(1, nearest.distance))
            XCTAssertEqual(hit.objectIndex, nearest.index)
        }
        XCTAssertGreaterThan(hits, 2000, "Most random rays should hit the ground or a sphere")
    }
}
