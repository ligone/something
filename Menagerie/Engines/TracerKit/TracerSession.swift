import Dispatch
import Foundation

/// Runs a `TracerRenderer` on a dedicated background thread and streams
/// tone-mapped frames to a callback.
///
/// Callers describe what they want with a `Configuration` (world, camera,
/// resolution and settings) and submit it whenever it changes. The session
/// does the rest:
/// - It cancels a pass in flight within a row or two when new work arrives,
///   which keeps camera drags responsive. It never cancels two passes in a
///   row for camera changes, so a continuous drag still produces frames.
/// - It rebuilds the renderer only when the world or resolution changes, and
///   otherwise just restarts accumulation.
/// - It publishes at most `maxFramesPerSecond` frames, and fewer once the
///   image has mostly converged.
/// - It stops at `targetSamples` samples per pixel and sleeps until something
///   changes, so a converged image costs no CPU.
///
/// `onFrame` runs on the render thread. UI code should hop to its own actor.
/// Call `stop()` when done: the session ends its thread, and a stopped
/// session can't be reused.
public final class TracerSession: @unchecked Sendable {
    public struct Configuration: Sendable, Equatable {
        public var world: TracerWorld
        public var camera: TracerCamera
        public var width: Int
        public var height: Int
        public var settings: TracerRenderSettings

        public init(world: TracerWorld, camera: TracerCamera, width: Int, height: Int,
                    settings: TracerRenderSettings = TracerRenderSettings()) {
            self.world = world
            self.camera = camera
            self.width = max(width, 1)
            self.height = max(height, 1)
            self.settings = settings
        }

        public static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            lhs.world === rhs.world && lhs.camera == rhs.camera && lhs.width == rhs.width
                && lhs.height == rhs.height && lhs.settings == rhs.settings
        }
    }

    public enum State: Sendable, Equatable {
        case rendering
        case paused
        case converged
    }

    /// One published image plus the statistics that go with it.
    public struct Frame: Sendable {
        /// RGBA8 pixels in sRGB, row-major, top row first.
        public let pixels: [UInt8]
        public let width: Int
        public let height: Int
        public let samplesPerPixel: Int
        public let targetSamples: Int
        /// A smoothed throughput estimate.
        public let raysPerSecond: Double
        /// Seconds spent rendering since the last restart, excluding pauses.
        public let elapsed: Double
        public let state: State
        /// Increments whenever accumulation restarts.
        public let generation: Int

        public var progress: Double {
            min(1, Double(samplesPerPixel) / Double(max(targetSamples, 1)))
        }
    }

    public let targetSamples: Int
    public let maxFramesPerSecond: Double

    private let onFrame: @Sendable (Frame) -> Void
    private let condition = NSCondition()

    // Guarded by `condition`.
    private var pending: Configuration?
    private var lastSubmitted: Configuration?
    private var restartRequested = false
    private var publishRequested = false
    private var exposure: Float
    private var paused = false
    private var stopped = false
    private var threadStarted = false
    /// The world and size the running pass renders, so workers can tell
    /// whether pending work makes that pass worthless.
    private var activeWorld: ObjectIdentifier?
    private var activeWidth = 0
    private var activeHeight = 0
    /// Set after a cancelled pass. The next pass then finishes even if the
    /// camera keeps moving, so a stream of small changes can't starve the
    /// display.
    private var protectPass = false

    public init(targetSamples: Int = 4096, maxFramesPerSecond: Double = 30, exposure: Float = 0,
                onFrame: @escaping @Sendable (Frame) -> Void) {
        self.targetSamples = max(targetSamples, 1)
        self.maxFramesPerSecond = max(maxFramesPerSecond, 1)
        self.exposure = exposure
        self.onFrame = onFrame
    }

    /// Renders `configuration`, restarting accumulation if it differs from the
    /// last one submitted. The first call starts the render thread.
    public func submit(_ configuration: Configuration) {
        condition.lock()
        defer { condition.unlock() }
        guard !stopped, configuration != lastSubmitted else { return }
        lastSubmitted = configuration
        pending = configuration
        if !threadStarted {
            threadStarted = true
            let thread = Thread { [self] in run() }
            thread.name = "TracerSession"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        condition.signal()
    }

    /// Changes the exposure, in stops, and republishes the current image
    /// without restarting accumulation.
    public func setExposure(_ stops: Float) {
        condition.lock()
        defer { condition.unlock() }
        guard stops != exposure else { return }
        exposure = stops
        publishRequested = true
        condition.signal()
    }

    public func setPaused(_ isPaused: Bool) {
        condition.lock()
        defer { condition.unlock() }
        guard isPaused != paused else { return }
        paused = isPaused
        publishRequested = true
        condition.signal()
    }

    /// Discards the accumulated image and starts converging again.
    public func restart() {
        condition.lock()
        defer { condition.unlock() }
        restartRequested = true
        condition.signal()
    }

    /// Ends the render thread. A pass in flight is abandoned within a row or
    /// two. No frames are delivered after the thread notices.
    public func stop() {
        condition.lock()
        defer { condition.unlock() }
        stopped = true
        condition.signal()
    }

    /// Polled by render workers between rows. Stopping, or a new world or
    /// resolution, always cancels. A camera or settings change cancels unless
    /// the previous pass was already cancelled.
    private var shouldCancelPass: Bool {
        condition.lock()
        defer { condition.unlock() }
        if stopped { return true }
        if let pending, ObjectIdentifier(pending.world) != activeWorld
            || pending.width != activeWidth || pending.height != activeHeight {
            return true
        }
        return !protectPass && (pending != nil || restartRequested)
    }

    private func run() {
        var renderer: TracerRenderer?
        var current: Configuration?
        var generation = 0
        var elapsed = 0.0
        var smoothedRate = 0.0
        var lastPublish: UInt64 = 0
        var publishedState: State?
        var publishSoon = false
        var lastPassCancelled = false

        while true {
            condition.lock()
            while !stopped && pending == nil && !restartRequested && !publishRequested
                    && (paused || renderer == nil || renderer!.sampleCount >= targetSamples) {
                condition.wait()
            }
            if stopped {
                condition.unlock()
                return
            }
            let next = pending
            pending = nil
            let restart = restartRequested
            restartRequested = false
            publishSoon = publishSoon || publishRequested
            publishRequested = false
            let exposure = self.exposure
            let isPaused = paused
            condition.unlock()

            if let next {
                if let active = renderer, let previous = current, previous.world === next.world,
                   previous.width == next.width, previous.height == next.height {
                    active.restart(camera: next.camera, settings: next.settings)
                } else {
                    renderer = TracerRenderer(world: next.world, camera: next.camera, width: next.width,
                                              height: next.height, settings: next.settings)
                }
                current = next
            } else if restart {
                renderer?.restart()
            }
            guard let renderer else { continue }
            if next != nil || restart {
                generation += 1
                elapsed = 0
                publishSoon = true
            }

            if !isPaused && renderer.sampleCount < targetSamples {
                condition.lock()
                activeWorld = ObjectIdentifier(renderer.world)
                activeWidth = renderer.width
                activeHeight = renderer.height
                protectPass = lastPassCancelled
                condition.unlock()

                let stats = renderer.renderPass(shouldCancel: { [self] in shouldCancelPass })
                lastPassCancelled = !stats.completed
                guard stats.completed else { continue }
                elapsed += stats.duration
                let rate = stats.raysPerSecond
                smoothedRate = smoothedRate == 0 ? rate : smoothedRate * 0.85 + rate * 0.15
            }

            let samples = renderer.sampleCount
            guard samples > 0 else { continue }
            let state: State = samples >= targetSamples ? .converged : (isPaused ? .paused : .rendering)
            let now = DispatchTime.now().uptimeNanoseconds
            // Refresh at full rate while noise is visibly melting away, then
            // at a calmer 8 Hz.
            let interval = samples < 128 ? 1 / maxFramesPerSecond : max(1 / maxFramesPerSecond, 0.125)
            let due = Double(now &- lastPublish) / 1e9 >= interval
            guard publishSoon || due || state != publishedState else { continue }

            let frame = Frame(pixels: renderer.snapshotRGBA8(exposure: exposure), width: renderer.width,
                              height: renderer.height, samplesPerPixel: samples, targetSamples: targetSamples,
                              raysPerSecond: smoothedRate, elapsed: elapsed, state: state, generation: generation)
            condition.lock()
            let isStopped = stopped
            condition.unlock()
            if isStopped { return }
            onFrame(frame)
            lastPublish = now
            publishedState = state
            publishSoon = false
        }
    }
}
