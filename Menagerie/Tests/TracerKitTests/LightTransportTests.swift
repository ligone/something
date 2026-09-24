import Foundation
import TracerKit
import XCTest

/// Checks the integrator against answers known in closed form.
final class LightTransportTests: XCTestCase {
    /// No firefly clamp, and bounces effectively unlimited, so the estimator is
    /// unbiased.
    private let unbiased = TracerRenderSettings(maxBounces: 64, russianRouletteDepth: 3, indirectClamp: 0)
    private let white = TracerColor(1, 1, 1)
    private let down = SIMD3<Float>(0, -1, 0)

    private func world(sky: TracerSky, _ objects: [(String, TracerShape, TracerMaterial)]) -> TracerWorld {
        var scene = TracerScene(name: "Test", sky: sky, camera: TracerCamera(position: SIMD3<Float>(0, 0, 5), target: .zero))
        for object in objects { scene.add(object.0, object.1, object.2) }
        return TracerWorld(scene: scene)
    }

    private func assertColor(_ value: TracerColor, _ expected: TracerColor, accuracy: Float, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value.x, expected.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(value.y, expected.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(value.z, expected.z, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: White furnace

    /// An object that reflects all light, inside an environment that is
    /// uniformly 1, must be invisible: every path returns exactly radiance 1.
    /// Any energy the integrator loses or creates shows up here.
    func testWhiteFurnaceMakesLosslessMaterialsVanish() {
        let materials: [(String, TracerMaterial)] = [
            ("diffuse", .diffuse(white)),
            ("glossy coat", .glossy(white, roughness: 0)),
            ("mirror", .metal(white, fuzz: 0)),
            ("clear glass", .glass(indexOfRefraction: 1.5)),
        ]
        let rays = [
            TracerRay(origin: SIMD3<Float>(0, 0, 5), direction: SIMD3<Float>(0, 0, -1)),       // head-on
            TracerRay(origin: SIMD3<Float>(0.8, 0.3, 5), direction: SIMD3<Float>(0, 0, -1)),   // oblique
            TracerRay(origin: SIMD3<Float>(0, 0.97, 5), direction: SIMD3<Float>(0, 0, -1)),    // near grazing
        ]
        for (label, material) in materials {
            let furnace = world(sky: .uniform(white), [("Sphere", .sphere(center: .zero, radius: 1), material)])
            for (index, ray) in rays.enumerated() {
                let radiance = furnace.estimateRadiance(along: ray, samples: 6000, settings: unbiased, seed: UInt64(index + 1))
                assertColor(radiance, white, accuracy: 0.025, "\(label) sphere, ray \(index)")
            }
        }
    }

    /// The same test with interreflections: light bounces around inside an
    /// open white box many times before escaping, which exercises Russian
    /// roulette and the BVH.
    func testWhiteFurnaceWithInterreflections() {
        var scene = TracerScene(name: "Open box", sky: .uniform(white), camera: TracerCamera(position: SIMD3<Float>(0, 0, 5), target: .zero))
        let faces = TracerShape.box(center: .zero, size: SIMD3<Float>(2, 2, 2))
        for face in faces.dropFirst() {  // leave the +Z face open
            scene.add("Wall", face, .diffuse(white))
        }
        scene.add("Ball", .sphere(center: SIMD3<Float>(0.3, -0.5, -0.2), radius: 0.4), .diffuse(white))
        let box = TracerWorld(scene: scene)
        for (index, target) in [SIMD3<Float>(0, 0, -1), SIMD3<Float>(-0.9, 0.9, -0.5), SIMD3<Float>(0.3, -0.5, 0.2)].enumerated() {
            let origin = SIMD3<Float>(0, 0, 3)
            let radiance = box.estimateRadiance(along: TracerRay(origin: origin, direction: target - origin),
                                                samples: 20000, settings: unbiased, seed: UInt64(index + 10))
            assertColor(radiance, white, accuracy: 0.03, "Ray \(index) into the open box")
        }
    }

    // MARK: Direct lighting

    /// Configuration factor from a small patch to a parallel rectangle, with
    /// one rectangle corner directly above the patch: `a` and `b` are the
    /// rectangle's sides and `h` its height.
    private func cornerViewFactor(_ a: Double, _ b: Double, _ h: Double) -> Double {
        let x = a / h
        let y = b / h
        let sx = (1 + x * x).squareRoot()
        let sy = (1 + y * y).squareRoot()
        return (x / sx * atan(y / sx) + y / sy * atan(x / sy)) / (2 * Double.pi)
    }

    /// A diffuse floor under a downward-facing square light. The reflected
    /// radiance is exactly `albedo × radiance × F`, where F is the view factor.
    /// Getting this right requires light sampling and BSDF sampling, combined
    /// by MIS, to add up without double counting.
    func testQuadLightMatchesTheAnalyticViewFactor() {
        let albedo: Float = 0.8
        let emitted: Float = 5
        // (side, height): a small distant light, where light sampling
        // dominates, and a huge nearby one, where BSDF sampling does.
        for (side, height) in [(Float(1), Float(1)), (0.6, 2.5), (40, 0.1)] {
            let half = side / 2
            let light = TracerShape.quad(corner: SIMD3<Float>(-half, height, -half), edgeU: SIMD3<Float>(side, 0, 0),
                                         edgeV: SIMD3<Float>(0, 0, side))  // (1,0,0) × (0,0,1) faces down
            let scene = world(sky: .black, [
                ("Floor", .plane(point: .zero, normal: SIMD3<Float>(0, 1, 0)), .diffuse(TracerColor(repeating: albedo))),
                ("Light", light, .light(TracerColor(repeating: emitted))),
            ])
            let factor = 4 * cornerViewFactor(Double(half), Double(half), Double(height))
            let expected = Float(Double(albedo * emitted) * factor)
            let probe = TracerRay(origin: SIMD3<Float>(0, height / 2, 0), direction: down)
            for bounces in [1, 6] {
                var settings = unbiased
                settings.maxBounces = bounces
                let radiance = scene.estimateRadiance(along: probe, samples: 30000, settings: settings, seed: 99)
                XCTAssertEqual(radiance.x, expected, accuracy: expected * 0.02,
                               "Light \(side)×\(side) at height \(height), \(bounces) bounce(s): expected \(expected)")
            }
        }
    }

    /// A floor lit by a sun of angular radius θ straight overhead reflects
    /// `albedo × radiance × sin²θ`.
    func testSunLightMatchesAnalyticIrradiance() {
        let albedo: Float = 0.5
        for radius: Float in [0.5, 5, 20] {
            let sun = TracerSun(direction: SIMD3<Float>(0, 1, 0), angularRadius: radius, radiance: TracerColor(repeating: 100))
            let scene = world(sky: TracerSky(zenith: .zero, horizon: .zero, ground: .zero, sun: sun), [
                ("Floor", .plane(point: .zero, normal: SIMD3<Float>(0, 1, 0)), .diffuse(TracerColor(repeating: albedo))),
            ])
            let s = sin(Double(radius) * Double.pi / 180)
            let expected = Float(Double(albedo) * 100 * s * s)
            let radiance = scene.estimateRadiance(along: TracerRay(origin: SIMD3<Float>(0, 1, 0), direction: down),
                                                  samples: 20000, settings: unbiased, seed: 5)
            XCTAssertEqual(radiance.y, expected, accuracy: expected * 0.02, "Sun radius \(radius)°")
        }
    }

    func testQuadLightsEmitFromTheirFrontFaceOnly() {
        // (2, 0, 0) × (0, 2, 0) points along +Z.
        let panel = world(sky: .black, [
            ("Panel", .quad(corner: SIMD3<Float>(-1, -1, 0), edgeU: SIMD3<Float>(2, 0, 0), edgeV: SIMD3<Float>(0, 2, 0)),
             .light(TracerColor(3, 2, 1))),
        ])
        let front = panel.estimateRadiance(along: TracerRay(origin: SIMD3<Float>(0, 0, 5), direction: SIMD3<Float>(0, 0, -1)),
                                           samples: 4, settings: unbiased)
        assertColor(front, TracerColor(3, 2, 1), accuracy: 1e-6, "Seen from the front")
        let back = panel.estimateRadiance(along: TracerRay(origin: SIMD3<Float>(0, 0, -5), direction: SIMD3<Float>(0, 0, 1)),
                                          samples: 4, settings: unbiased)
        assertColor(back, .zero, accuracy: 1e-6, "Seen from behind")
    }

    // MARK: Media

    /// With index-matched glass nothing reflects or bends, so a ray through
    /// the center of a unit sphere crosses exactly 2 units of absorbing medium.
    func testGlassAbsorptionFollowsBeerLambert() {
        let tint = TracerColor(0.5, 0.25, 1)
        let scene = world(sky: .uniform(white), [
            ("Tinted glass", .sphere(center: .zero, radius: 1), .glass(indexOfRefraction: 1, transmittance: tint)),
        ])
        let radiance = scene.estimateRadiance(along: TracerRay(origin: SIMD3<Float>(0, 0, 5), direction: SIMD3<Float>(0, 0, -1)),
                                              samples: 16, settings: unbiased)
        assertColor(radiance, tint * tint, accuracy: 1e-4, "Transmittance is tint^distance")
    }

    // MARK: Firefly clamp

    func testIndirectClampOnlyLimitsIndirectLight() {
        // A bright panel seen directly keeps its full radiance...
        let panel = world(sky: .black, [
            ("Panel", .quad(corner: SIMD3<Float>(-1, -1, 0), edgeU: SIMD3<Float>(2, 0, 0), edgeV: SIMD3<Float>(0, 2, 0)),
             .light(TracerColor(repeating: 50))),
        ])
        var clamped = unbiased
        clamped.indirectClamp = 2
        let direct = panel.estimateRadiance(along: TracerRay(origin: SIMD3<Float>(0, 0, 5), direction: SIMD3<Float>(0, 0, -1)),
                                            samples: 4, settings: clamped)
        XCTAssertEqual(direct.x, 50, accuracy: 1e-4)

        // ...while a floor lit only indirectly (a small, intense panel faces the
        // ceiling, and the ceiling lights the floor) is dimmed by the clamp.
        let room = world(sky: .black, [
            ("Floor", .plane(point: .zero, normal: SIMD3<Float>(0, 1, 0)), .diffuse(TracerColor(repeating: 0.5))),
            ("Ceiling", .plane(point: SIMD3<Float>(0, 2, 0), normal: SIMD3<Float>(0, -1, 0)), .diffuse(TracerColor(repeating: 0.5))),
            ("Uplight", .quad(corner: SIMD3<Float>(-0.1, 1, -0.1), edgeU: SIMD3<Float>(0, 0, 0.2), edgeV: SIMD3<Float>(0.2, 0, 0)),
             .light(TracerColor(repeating: 10000))),
        ])
        let probe = TracerRay(origin: SIMD3<Float>(1, 0.5, 0), direction: down)
        let free = room.estimateRadiance(along: probe, samples: 20000, settings: unbiased, seed: 3)
        let limited = room.estimateRadiance(along: probe, samples: 20000, settings: clamped, seed: 3)
        XCTAssertGreaterThan(free.x, 2, "Unclamped, the bounced light is bright")
        XCTAssertGreaterThan(limited.x, 0, "Clamping dims indirect light but doesn't remove it")
        XCTAssertLessThan(limited.x, free.x * 0.5, "The clamp cuts off the spiky indirect contributions")
    }
}
