import Foundation
import TracerKit
import XCTest

final class SessionTests: XCTestCase {
    private let world = TracerWorld(scene: TracerScenePreset.studio.makeScene())

    private func configuration(width: Int = 24, height: Int = 16, camera: TracerCamera? = nil) -> TracerSession.Configuration {
        TracerSession.Configuration(world: world, camera: camera ?? world.scene.camera, width: width, height: height)
    }

    func testSessionConvergesAtTheTargetAndReportsProgress() {
        let log = FrameLog()
        let converged = expectation(description: "converged")
        converged.assertForOverFulfill = false
        let session = TracerSession(targetSamples: 6, maxFramesPerSecond: 240) { frame in
            log.append(frame)
            if frame.state == .converged { converged.fulfill() }
        }
        defer { session.stop() }
        session.submit(configuration())
        wait(for: [converged], timeout: 30)

        let last = log.last(where: { $0.state == .converged })
        XCTAssertEqual(last?.samplesPerPixel, 6)
        XCTAssertEqual(last?.pixels.count, 24 * 16 * 4)
        XCTAssertEqual(last?.progress, 1)
        XCTAssertEqual(last?.generation, 1)
        XCTAssertTrue(log.frames.allSatisfy { $0.samplesPerPixel <= 6 }, "Rendering stops at the target")
    }

    func testChangingTheCameraRestartsAccumulation() {
        let log = FrameLog()
        let first = expectation(description: "first convergence")
        let second = expectation(description: "second convergence")
        first.assertForOverFulfill = false
        second.assertForOverFulfill = false
        let session = TracerSession(targetSamples: 4, maxFramesPerSecond: 240) { frame in
            log.append(frame)
            guard frame.state == .converged else { return }
            if frame.generation == 1 { first.fulfill() }
            if frame.generation == 2 { second.fulfill() }
        }
        defer { session.stop() }
        session.submit(configuration())
        wait(for: [first], timeout: 30)

        session.submit(configuration())  // unchanged, so this is ignored
        var moved = world.scene.camera
        moved.position.x += 1
        session.submit(configuration(camera: moved))
        wait(for: [second], timeout: 30)
        XCTAssertFalse(log.frames.contains { $0.generation > 2 }, "An identical configuration doesn't restart")
    }

    func testExposureChangesRepublishWithoutRestarting() {
        let log = FrameLog()
        let converged = expectation(description: "converged")
        let republished = expectation(description: "republished")
        converged.assertForOverFulfill = false
        republished.assertForOverFulfill = false
        let session = TracerSession(targetSamples: 3, maxFramesPerSecond: 240) { frame in
            log.append(frame)
            if frame.state == .converged {
                if log.frames.filter({ $0.state == .converged }).count >= 2 { republished.fulfill() } else { converged.fulfill() }
            }
        }
        defer { session.stop() }
        session.submit(configuration())
        wait(for: [converged], timeout: 30)
        session.setExposure(2)
        wait(for: [republished], timeout: 30)

        let frames = log.frames.filter { $0.state == .converged }
        XCTAssertEqual(frames.first?.generation, frames.last?.generation, "Exposure doesn't restart accumulation")
        let brightness = { (frame: TracerSession.Frame) in frame.pixels.reduce(0) { $0 + Int($1) } }
        if let before = frames.first, let after = frames.last {
            XCTAssertGreaterThan(brightness(after), brightness(before))
        }
    }

    /// A drag submits a new camera faster than passes finish. Cancelling every
    /// pass would starve the display, so the session must still publish.
    func testContinuousCameraChangesStillProduceFrames() {
        let log = FrameLog()
        let session = TracerSession(targetSamples: 100_000, maxFramesPerSecond: 1000) { frame in
            log.append(frame)
        }
        defer { session.stop() }
        // A scene and size where one pass takes much longer than the gap
        // between camera updates.
        let cornell = TracerWorld(scene: TracerScenePreset.cornellBox.makeScene())
        var camera = cornell.scene.camera
        let deadline = Date().addingTimeInterval(1.5)
        var step: Float = 0
        while Date() < deadline {
            step += 1
            camera.position.x = 0.001 * step
            session.submit(TracerSession.Configuration(world: cornell, camera: camera, width: 320, height: 240))
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertGreaterThan(log.frames.count, 5, "Frames keep flowing during a continuous drag")
        let generations = Set(log.frames.map(\.generation))
        XCTAssertGreaterThan(generations.count, 5, "The frames follow the moving camera")
    }

    func testStopEndsFrameDelivery() {
        let log = FrameLog()
        let started = expectation(description: "first frame")
        started.assertForOverFulfill = false
        let session = TracerSession(targetSamples: 100_000, maxFramesPerSecond: 240) { frame in
            log.append(frame)
            started.fulfill()
        }
        session.submit(configuration(width: 64, height: 48))
        wait(for: [started], timeout: 30)
        session.stop()
        Thread.sleep(forTimeInterval: 0.3)
        let count = log.frames.count
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(log.frames.count, count, "No frames arrive after stop()")
    }
}

/// Collects frames delivered on the render thread.
final class FrameLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TracerSession.Frame] = []

    func append(_ frame: TracerSession.Frame) {
        lock.lock()
        storage.append(frame)
        lock.unlock()
    }

    var frames: [TracerSession.Frame] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func last(where predicate: (TracerSession.Frame) -> Bool) -> TracerSession.Frame? {
        frames.last(where: predicate)
    }
}
