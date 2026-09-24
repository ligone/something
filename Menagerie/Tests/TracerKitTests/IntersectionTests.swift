import TracerKit
import XCTest

final class IntersectionTests: XCTestCase {
    private let sphere = TracerShape.sphere(center: SIMD3<Float>(0, 0, -5), radius: 1)

    // MARK: Spheres

    func testSphereHitFromOutside() throws {
        let hit = try XCTUnwrap(sphere.intersect(TracerRay(origin: .zero, direction: SIMD3<Float>(0, 0, -1))))
        XCTAssertEqual(hit.distance, 4, accuracy: 1e-5)
        assertEqual(hit.point, SIMD3<Float>(0, 0, -4))
        assertEqual(hit.normal, SIMD3<Float>(0, 0, 1))
        XCTAssertTrue(hit.isFrontFace)
    }

    func testSphereHitFromInsideReportsBackFace() throws {
        let ray = TracerRay(origin: SIMD3<Float>(0, 0, -5), direction: SIMD3<Float>(0, 0, -1))
        let hit = try XCTUnwrap(sphere.intersect(ray))
        XCTAssertEqual(hit.distance, 1, accuracy: 1e-5)
        assertEqual(hit.normal, SIMD3<Float>(0, 0, -1))
        XCTAssertFalse(hit.isFrontFace, "An exiting ray sees the inside of the surface")
    }

    func testSphereMissesRaysPointingAwayOrPassingBeside() {
        XCTAssertNil(sphere.intersect(TracerRay(origin: .zero, direction: SIMD3<Float>(0, 0, 1))))
        XCTAssertNil(sphere.intersect(TracerRay(origin: SIMD3<Float>(1.001, 0, 0), direction: SIMD3<Float>(0, 0, -1))))
        XCTAssertNil(sphere.intersect(TracerRay(origin: SIMD3<Float>(0, 0, -10), direction: SIMD3<Float>(0, 0, -1))),
                     "A sphere entirely behind the ray origin is not hit")
    }

    func testTangentRayGrazesTheSphere() throws {
        // The discriminant is exactly zero here, so both roots coincide.
        let ray = TracerRay(origin: SIMD3<Float>(1, 0, 0), direction: SIMD3<Float>(0, 0, -1))
        let hit = try XCTUnwrap(sphere.intersect(ray))
        XCTAssertEqual(hit.distance, 5, accuracy: 1e-5)
        assertEqual(hit.normal, SIMD3<Float>(1, 0, 0))
    }

    func testSphereRespectsTheDistanceInterval() throws {
        let ray = TracerRay(origin: .zero, direction: SIMD3<Float>(0, 0, -1))
        XCTAssertNil(sphere.intersect(ray, tMax: 3.9))
        let far = try XCTUnwrap(sphere.intersect(ray, tMin: 4.5))
        XCTAssertEqual(far.distance, 6, accuracy: 1e-5, "Skipping the near root must return the far one")
    }

    func testNegativeRadiusMakesAHollowBubble() throws {
        let bubble = TracerShape.sphere(center: SIMD3<Float>(0, 0, -5), radius: -1)
        let hit = try XCTUnwrap(bubble.intersect(TracerRay(origin: .zero, direction: SIMD3<Float>(0, 0, -1))))
        assertEqual(hit.normal, SIMD3<Float>(0, 0, -1), "Normals of a negative sphere point inward")
        XCTAssertFalse(hit.isFrontFace)
    }

    func testSphereIsAccurateFarFromTheOrigin() throws {
        // A small sphere far away stresses the discriminant. The closest-approach
        // formulation keeps this hit accurate.
        let tiny = TracerShape.sphere(center: SIMD3<Float>(0, 0, -5000), radius: 0.01)
        let hit = try XCTUnwrap(tiny.intersect(TracerRay(origin: .zero, direction: SIMD3<Float>(0, 0, -1))))
        XCTAssertEqual(hit.distance, 4999.99, accuracy: 2e-3)
    }

    // MARK: Quads

    /// A 2 × 2 square in the plane z = −3, facing +Z.
    private let square = TracerShape.quad(corner: SIMD3<Float>(-1, -1, -3), edgeU: SIMD3<Float>(2, 0, 0),
                                          edgeV: SIMD3<Float>(0, 2, 0))

    func testQuadHitHasDistanceNormalAndFace() throws {
        let hit = try XCTUnwrap(square.intersect(TracerRay(origin: .zero, direction: SIMD3<Float>(0, 0, -1))))
        XCTAssertEqual(hit.distance, 3, accuracy: 1e-6)
        assertEqual(hit.normal, SIMD3<Float>(0, 0, 1))
        XCTAssertTrue(hit.isFrontFace)
    }

    func testQuadBackFaceIsReported() throws {
        let ray = TracerRay(origin: SIMD3<Float>(0.3, 0.2, -6), direction: SIMD3<Float>(0, 0, 1))
        let hit = try XCTUnwrap(square.intersect(ray))
        XCTAssertEqual(hit.distance, 3, accuracy: 1e-6)
        XCTAssertFalse(hit.isFrontFace)
    }

    func testQuadEdgesAndCornersAreInclusive() {
        let down = SIMD3<Float>(0, 0, -1)
        XCTAssertNotNil(square.intersect(TracerRay(origin: SIMD3<Float>(-1, -1, 0), direction: down)), "Corner")
        XCTAssertNotNil(square.intersect(TracerRay(origin: SIMD3<Float>(1, 1, 0), direction: down)), "Opposite corner")
        XCTAssertNotNil(square.intersect(TracerRay(origin: SIMD3<Float>(1, 0, 0), direction: down)), "Edge")
        XCTAssertNil(square.intersect(TracerRay(origin: SIMD3<Float>(1.0001, 0, 0), direction: down)), "Just outside")
        XCTAssertNil(square.intersect(TracerRay(origin: SIMD3<Float>(0, -1.0001, 0), direction: down)), "Just below")
    }

    func testQuadIgnoresParallelAndBackwardRays() {
        XCTAssertNil(square.intersect(TracerRay(origin: SIMD3<Float>(-5, 0, -3), direction: SIMD3<Float>(1, 0, 0))),
                     "A ray lying in the quad's plane never registers a hit")
        XCTAssertNil(square.intersect(TracerRay(origin: SIMD3<Float>(0, 0, -4), direction: SIMD3<Float>(0, 0, -1))))
    }

    func testParallelogramUsesPlanarCoordinates() {
        // A slanted parallelogram. The point (0.5, 0.9) lies inside its
        // bounding rectangle but outside the shape itself.
        let slanted = TracerShape.quad(corner: .zero, edgeU: SIMD3<Float>(2, 0, 0), edgeV: SIMD3<Float>(1, 1, 0))
        let down = SIMD3<Float>(0, 0, -1)
        XCTAssertNotNil(slanted.intersect(TracerRay(origin: SIMD3<Float>(2.9, 0.95, 1), direction: down)))
        XCTAssertNil(slanted.intersect(TracerRay(origin: SIMD3<Float>(0.5, 0.9, 1), direction: down)))
        XCTAssertEqual(slanted.area, 2, accuracy: 1e-6)
    }

    // MARK: Planes and boxes

    func testPlaneIntersection() throws {
        let ground = TracerShape.plane(point: .zero, normal: SIMD3<Float>(0, 1, 0))
        let hit = try XCTUnwrap(ground.intersect(TracerRay(origin: SIMD3<Float>(3, 2, 1), direction: SIMD3<Float>(0, -1, 0))))
        XCTAssertEqual(hit.distance, 2, accuracy: 1e-6)
        XCTAssertTrue(hit.isFrontFace)
        XCTAssertNil(ground.intersect(TracerRay(origin: SIMD3<Float>(0, 2, 0), direction: SIMD3<Float>(1, 0, 0))))
        XCTAssertNil(ground.intersect(TracerRay(origin: SIMD3<Float>(0, 2, 0), direction: SIMD3<Float>(0, 1, 0))))
    }

    func testBoxFacesPointOutwardForAnyYaw() {
        for yaw: Float in [0, 17, 45, 90, 200] {
            let center = SIMD3<Float>(1, 2, 3)
            let faces = TracerShape.box(center: center, size: SIMD3<Float>(2, 4, 1), yawDegrees: yaw)
            XCTAssertEqual(faces.count, 6)
            var totalArea: Float = 0
            for face in faces {
                guard case let .quad(corner, u, v) = face else { return XCTFail("Boxes are made of quads") }
                let faceCenter = corner + (u + v) * 0.5
                let n = SIMD3<Float>(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
                let outward = faceCenter - center
                XCTAssertGreaterThan((n * outward).sum(), 0, "Face normal must point away from the center (yaw \(yaw))")
                totalArea += face.area
            }
            let expectedArea: Float = 28  // 2 × (2·4 + 4·1 + 2·1)
            XCTAssertEqual(totalArea, expectedArea, accuracy: 1e-3)
        }
    }

    func testRotatedBoxBlocksRaysThroughItsCenter() throws {
        var scene = TracerScene(name: "Box", camera: TracerCamera(position: SIMD3<Float>(0, 0, 10), target: .zero))
        scene.addBox("Box", center: .zero, size: SIMD3<Float>(1, 1, 1), yawDegrees: 45, material: .diffuse(TracerColor(0.5, 0.5, 0.5)))
        let world = TracerWorld(scene: scene)
        let hit = try XCTUnwrap(world.intersect(TracerRay(origin: SIMD3<Float>(0.1, 0, 10), direction: SIMD3<Float>(0, 0, -1))))
        // A unit cube turned 45° presents a vertical edge to +Z, √2 / 2 from its
        // center. Its front faces slope away at 45°, so 0.1 to the side the
        // surface sits 0.1 further back.
        XCTAssertEqual(hit.distance, 10 - (0.5 * Float(2).squareRoot() - 0.1), accuracy: 1e-3)
        XCTAssertEqual(hit.objectIndex.map { scene.objects[$0].name }, "Box")
    }

    private func assertEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ message: String = "", accuracy: Float = 1e-5,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, message, file: file, line: line)
    }
}
