import Foundation
import TracerKit
import XCTest

final class CameraTests: XCTestCase {
    private let camera = TracerCamera(position: SIMD3<Float>(0, 0, 5), target: .zero, verticalFieldOfView: 90)

    func testFocusDistanceDefaultsToTheTarget() {
        XCTAssertEqual(camera.focusDistance, 5, accuracy: 1e-6)
        XCTAssertEqual(camera.viewDirection.z, -1, accuracy: 1e-6)
    }

    func testCenterRayLooksAtTheTarget() {
        let ray = camera.centerRay(x: 0.5, y: 0.5, aspectRatio: 1.5)
        XCTAssertEqual(ray.origin, camera.position)
        XCTAssertEqual(ray.direction.x, 0, accuracy: 1e-6)
        XCTAssertEqual(ray.direction.y, 0, accuracy: 1e-6)
        XCTAssertEqual(ray.direction.z, -1, accuracy: 1e-6)
    }

    func testImageOrientationAndFieldOfView() {
        // With a 90° vertical field of view, the top edge is 45° above the axis.
        let top = camera.centerRay(x: 0.5, y: 0, aspectRatio: 1)
        XCTAssertEqual(top.direction.y, sin(Float.pi / 4), accuracy: 1e-5, "y = 0 is the top of the image")
        XCTAssertEqual(top.direction.z, -cos(Float.pi / 4), accuracy: 1e-5)

        let left = camera.centerRay(x: 0, y: 0.5, aspectRatio: 2)
        XCTAssertLessThan(left.direction.x, 0, "x = 0 is the left of the image")
        // At aspect 2, the half-width at unit depth is 2 × tan(45°) = 2.
        XCTAssertEqual(left.direction.x / -left.direction.z, -2, accuracy: 1e-4)
    }

    func testFramingWidensTheViewForNarrowImages() {
        let authored = TracerCamera(position: SIMD3<Float>(0, 0, 5), target: .zero, verticalFieldOfView: 30)
        let wide = authored.framed(forAspectRatio: 2, referenceAspectRatio: 1.5)
        XCTAssertEqual(wide.verticalFieldOfView, 30, "Wider images keep the authored vertical field of view")

        let narrow = authored.framed(forAspectRatio: 0.75, referenceAspectRatio: 1.5)
        let authoredHalfWidth = tan(Float(15) * Float.pi / 180) * 1.5
        let narrowHalfWidth = tan(narrow.verticalFieldOfView * Float.pi / 360) * 0.75
        XCTAssertEqual(narrowHalfWidth, authoredHalfWidth, accuracy: 1e-5, "Narrow images keep the horizontal framing")
        XCTAssertGreaterThan(narrow.verticalFieldOfView, 30)
    }

    func testOrbitRoundTripsThroughACamera() {
        let original = TracerCamera(position: SIMD3<Float>(3, 4, 12), target: SIMD3<Float>(1, 1, 0))
        let orbit = TracerOrbit(camera: original)
        XCTAssertEqual(orbit.distance, Float(157).squareRoot(), accuracy: 1e-4)  // |(2, 3, 12)|
        let position = orbit.position
        XCTAssertEqual(position.x, 3, accuracy: 1e-4)
        XCTAssertEqual(position.y, 4, accuracy: 1e-4)
        XCTAssertEqual(position.z, 12, accuracy: 1e-4)

        let rebuilt = orbit.camera(lens: original)
        XCTAssertEqual(rebuilt.target, original.target)
        XCTAssertEqual(rebuilt.focusDistance, original.focusDistance, "The lens settings carry over")
    }

    func testOrbitAnglesAndClamping() {
        let front = TracerOrbit(target: .zero, yaw: 0, pitch: 0, distance: 2)
        XCTAssertEqual(front.position.z, 2, accuracy: 1e-6, "Yaw 0 sits on the +Z side")

        let above = TracerOrbit(target: .zero, yaw: 0, pitch: Float.pi / 2, distance: 2)
        XCTAssertEqual(above.position.y, 2, accuracy: 1e-5, "Positive pitch looks down from above")

        let limits = TracerOrbitLimits(yaw: -0.5...0.5, pitch: 0...1, distance: 1...10)
        let clamped = TracerOrbit(target: .zero, yaw: 2, pitch: -1, distance: 50).clamped(to: limits)
        XCTAssertEqual(clamped.yaw, 0.5)
        XCTAssertEqual(clamped.pitch, 0)
        XCTAssertEqual(clamped.distance, 10)

        let free = TracerOrbit(target: .zero, yaw: 7, pitch: 0.5, distance: 3).clamped(to: TracerOrbitLimits())
        XCTAssertEqual(free.yaw, 7, "Without a yaw range the camera may spin freely")
    }
}
