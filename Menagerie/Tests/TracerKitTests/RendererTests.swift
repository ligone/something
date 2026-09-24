import Foundation
import TracerKit
import XCTest

final class RendererTests: XCTestCase {
    private lazy var cornell = TracerWorld(scene: TracerScenePreset.cornellBox.makeScene())

    private func renderer(width: Int = 24, height: Int = 16, seed: UInt64 = 7) -> TracerRenderer {
        TracerRenderer(world: cornell, camera: cornell.scene.camera, width: width, height: height, seed: seed)
    }

    // MARK: Progressive accumulation

    func testEachPassAddsOneSamplePerPixel() {
        let r = renderer()
        XCTAssertEqual(r.sampleCount, 0)
        for expected in 1...3 {
            let stats = r.renderPass()
            XCTAssertTrue(stats.completed)
            XCTAssertGreaterThanOrEqual(stats.rays, UInt64(24 * 16), "At least one camera ray per pixel")
            XCTAssertGreaterThan(stats.raysPerSecond, 0)
            XCTAssertEqual(r.sampleCount, expected)
        }
        XCTAssertGreaterThan(r.totalRays, UInt64(3 * 24 * 16))
    }

    func testTheSameSeedRendersTheSameImage() {
        func render(seed: UInt64) -> [UInt8] {
            let r = renderer(width: 32, height: 20, seed: seed)
            for _ in 0..<3 { r.renderPass() }
            return r.snapshotRGBA8()
        }
        let first = render(seed: 42)
        XCTAssertEqual(first, render(seed: 42), "Row-seeded streams make rendering independent of thread scheduling")
        XCTAssertNotEqual(first, render(seed: 43))
    }

    func testRestartClearsTheImageAndAppliesTheNewCamera() {
        let r = renderer()
        r.renderPass()
        var moved = r.camera
        moved.position.x += 0.5
        r.restart(camera: moved)
        XCTAssertEqual(r.sampleCount, 0)
        XCTAssertEqual(r.totalRays, 0)
        XCTAssertEqual(r.camera, moved)
        XCTAssertTrue(r.snapshotLinear().allSatisfy { $0 == 0 })
    }

    func testCancelledPassLeavesAConsistentImage() {
        let r = renderer(width: 16, height: 40)
        r.renderPass()
        let rowsStarted = LockedCounter()
        let stats = r.renderPass(shouldCancel: { rowsStarted.increment() > 10 })
        XCTAssertFalse(stats.completed)
        XCTAssertEqual(r.sampleCount, 1, "Some rows still have only the first sample")
        XCTAssertTrue(r.snapshotLinear().allSatisfy { $0.isFinite && $0 >= 0 })

        XCTAssertTrue(r.renderPass().completed)
        XCTAssertEqual(r.sampleCount, 2)
    }

    // MARK: Tone mapping and snapshots

    func testToneMappingIsBoundedAndMonotonic() {
        var previous: Float = -1
        for step in 0...4000 {
            let value = Float(step) * 0.005
            let mapped = TracerToneMapper.acesFilmic(TracerColor(repeating: value))
            XCTAssertTrue((0...1).contains(mapped.x), "Out of range at \(value)")
            XCTAssertGreaterThanOrEqual(mapped.x, previous, "Not monotonic at \(value)")
            previous = mapped.x
        }
        XCTAssertEqual(TracerToneMapper.acesFilmic(.zero), .zero)
        for extreme: Float in [1e6, 1e30, .infinity] {
            XCTAssertEqual(TracerToneMapper.acesFilmic(TracerColor(repeating: extreme)).x, 1, accuracy: 1e-4)
        }
        for invalid: Float in [-1, -.infinity, .nan] {
            XCTAssertEqual(TracerToneMapper.acesFilmic(TracerColor(repeating: invalid)), .zero)
        }
    }

    func testSRGBEncodingEndpointsAndContinuity() {
        XCTAssertEqual(TracerToneMapper.encodeSRGB(0), 0)
        XCTAssertEqual(TracerToneMapper.encodeSRGB(1), 1, accuracy: 1e-6)
        let knee: Float = 0.003_130_8
        XCTAssertEqual(TracerToneMapper.encodeSRGB(knee), TracerToneMapper.encodeSRGB(knee.nextUp), accuracy: 1e-4)
        XCTAssertEqual(TracerToneMapper.displayColor(.zero, exposure: 0), SIMD3<UInt8>(0, 0, 0))
        XCTAssertEqual(TracerToneMapper.displayColor(TracerColor(repeating: 1e4), exposure: 0), SIMD3<UInt8>(255, 255, 255))
    }

    func testSnapshotLayoutAndExposure() {
        let r = renderer(width: 20, height: 10)
        let empty = r.snapshotRGBA8()
        XCTAssertEqual(empty.count, 20 * 10 * 4)
        for pixel in stride(from: 0, to: empty.count, by: 4) {
            XCTAssertEqual(empty[pixel + 3], 255, "Alpha is opaque")
            XCTAssertEqual(empty[pixel], 0, "No samples means black")
        }

        for _ in 0..<4 { r.renderPass() }
        let normal = r.snapshotRGBA8(exposure: 0)
        let brighter = r.snapshotRGBA8(exposure: 2)
        let sum = { (bytes: [UInt8]) in bytes.reduce(0) { $0 + Int($1) } }
        XCTAssertGreaterThan(sum(brighter), sum(normal), "Two stops up is brighter")
        XCTAssertEqual(r.snapshotLinear().count, 20 * 10 * 3)
    }

    // MARK: Picking

    func testPickingReportsDistanceAndFocusDepth() throws {
        var scene = TracerScene(name: "Pick", camera: TracerCamera(position: .zero, target: SIMD3<Float>(0, 0, -1), verticalFieldOfView: 60))
        scene.add("Ball", .sphere(center: SIMD3<Float>(0, 0, -5), radius: 1), .diffuse(TracerColor(0.5, 0.5, 0.5)))
        scene.add("Wall", .quad(corner: SIMD3<Float>(-20, -20, -10), edgeU: SIMD3<Float>(40, 0, 0), edgeV: SIMD3<Float>(0, 40, 0)),
                  .diffuse(TracerColor(0.5, 0.5, 0.5)))
        let world = TracerWorld(scene: scene)

        let center = try XCTUnwrap(world.pick(camera: scene.camera, x: 0.5, y: 0.5, aspectRatio: 1.5))
        XCTAssertEqual(center.distance, 4, accuracy: 1e-4)
        XCTAssertEqual(center.focusDistance, 4, accuracy: 1e-4)
        XCTAssertEqual(center.objectName, "Ball")

        // Off-axis, the wall is further along the ray than along the view
        // direction. Focus uses the depth along the view direction, because
        // the plane of focus is perpendicular to it.
        let side = try XCTUnwrap(world.pick(camera: scene.camera, x: 0.9, y: 0.5, aspectRatio: 1.5))
        XCTAssertEqual(side.objectName, "Wall")
        XCTAssertEqual(side.focusDistance, 10, accuracy: 1e-3)
        XCTAssertGreaterThan(side.distance, 10.5)

        let away = TracerCamera(position: .zero, target: SIMD3<Float>(0, 0, 1))
        XCTAssertNil(world.pick(camera: away, x: 0.5, y: 0.5, aspectRatio: 1), "Nothing behind the camera")

        let r = TracerRenderer(world: world, camera: scene.camera, width: 300, height: 200)
        let pixelPick = try XCTUnwrap(r.pick(x: 150, y: 100))
        XCTAssertEqual(pixelPick.distance, 4, accuracy: 1e-3)
    }
}

/// A thread-safe counter for cancellation callbacks, which run on worker threads.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    /// Increments and returns the new value.
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
