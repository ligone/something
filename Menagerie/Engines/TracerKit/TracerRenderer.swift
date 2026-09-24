import Dispatch
import Foundation

/// Light-transport parameters for the path tracer.
public struct TracerRenderSettings: Sendable, Equatable {
    /// The maximum number of scattering events per path. With 1 you get
    /// direct lighting only, and higher values add indirect bounces.
    public var maxBounces: Int
    /// The bounce at which Russian roulette may start ending low-energy paths.
    public var russianRouletteDepth: Int
    /// The largest RGB component any single indirect contribution may reach.
    /// It suppresses rare, very bright "firefly" paths, such as caustics seen
    /// through glass, at the cost of slight darkening. `0` turns it off, and
    /// the estimator is then unbiased.
    public var indirectClamp: Float

    public init(maxBounces: Int = 8, russianRouletteDepth: Int = 3, indirectClamp: Float = 4) {
        self.maxBounces = maxBounces
        self.russianRouletteDepth = russianRouletteDepth
        self.indirectClamp = indirectClamp
    }
}

/// What one progressive pass did.
public struct TracerPassStats: Sendable, Equatable {
    /// Rays traced: camera, bounce and shadow rays.
    public var rays: UInt64
    /// Wall-clock duration in seconds.
    public var duration: Double
    /// `false` when a cancellation request stopped the pass early. Rows that
    /// finished keep their extra sample, so the image stays consistent.
    public var completed: Bool

    public var raysPerSecond: Double {
        duration > 0 ? Double(rays) / duration : 0
    }
}

/// A progressive Monte Carlo renderer.
///
/// Each call to `renderPass()` traces one new path per pixel on every core
/// (`DispatchQueue.concurrentPerform` over image rows) and adds it to a
/// floating-point accumulation buffer. Snapshots divide by the sample count,
/// so the image converges while you watch.
///
/// Renders are deterministic. Each row's random stream is seeded from the
/// renderer seed, the row index and that row's sample index, so thread
/// scheduling never changes the result.
///
/// The renderer is thread-safe. Passes, restarts and snapshots are serialized
/// by a lock, so a snapshot requested mid-pass waits for the pass to finish.
/// The read-only properties never wait for a pass.
public final class TracerRenderer: @unchecked Sendable {
    public let world: TracerWorld
    public let width: Int
    public let height: Int
    public let seed: UInt64

    /// Serializes passes, restarts and snapshots.
    private let passLock = NSLock()
    /// Guards the small mutable state below. It is never held for long.
    private let stateLock = NSLock()
    private var currentCamera: TracerCamera
    private var currentSettings: TracerRenderSettings
    private var completeSamples = 0
    private var raysTraced: UInt64 = 0

    private let accumulation: UnsafeMutablePointer<Float>
    private let rowSamples: UnsafeMutablePointer<Int32>
    private let rowRays: UnsafeMutablePointer<UInt64>

    public init(world: TracerWorld, camera: TracerCamera, width: Int, height: Int,
                settings: TracerRenderSettings = TracerRenderSettings(), seed: UInt64 = 0x5EED_CAFE) {
        self.world = world
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.seed = seed
        currentCamera = camera
        currentSettings = settings
        let pixels = self.width * self.height
        accumulation = .allocate(capacity: pixels * 3)
        accumulation.initialize(repeating: 0, count: pixels * 3)
        rowSamples = .allocate(capacity: self.height)
        rowSamples.initialize(repeating: 0, count: self.height)
        rowRays = .allocate(capacity: self.height)
        rowRays.initialize(repeating: 0, count: self.height)
    }

    deinit {
        accumulation.deallocate()
        rowSamples.deallocate()
        rowRays.deallocate()
    }

    public var camera: TracerCamera {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentCamera
    }

    public var settings: TracerRenderSettings {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentSettings
    }

    /// Samples per pixel that every pixel has received.
    public var sampleCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return completeSamples
    }

    /// Rays traced since the last restart.
    public var totalRays: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return raysTraced
    }

    public var aspectRatio: Float {
        Float(width) / Float(height)
    }

    /// Clears the accumulated image, optionally switching camera or settings.
    public func restart(camera: TracerCamera? = nil, settings: TracerRenderSettings? = nil) {
        passLock.lock()
        defer { passLock.unlock() }
        stateLock.lock()
        if let camera { currentCamera = camera }
        if let settings { currentSettings = settings }
        completeSamples = 0
        raysTraced = 0
        stateLock.unlock()
        accumulation.update(repeating: 0, count: width * height * 3)
        rowSamples.update(repeating: 0, count: height)
    }

    /// Adds one sample per pixel. The caller's thread blocks until the pass
    /// finishes, while the work runs on every core.
    ///
    /// - Parameter shouldCancel: Polled from worker threads before each row,
    ///   so it must be thread-safe. Returning `true` skips the remaining rows.
    @discardableResult
    public func renderPass(shouldCancel: (@Sendable () -> Bool)? = nil) -> TracerPassStats {
        passLock.lock()
        defer { passLock.unlock() }

        stateLock.lock()
        let camera = currentCamera
        let settings = currentSettings
        let samplesBefore = completeSamples
        stateLock.unlock()

        let rig = CameraRig(camera: camera, aspectRatio: aspectRatio)
        let tracer = PathKernel(world: world.kernel, settings: settings)
        let width = self.width
        let seed = self.seed
        let buffers = RowBuffers(accumulation: accumulation, rowSamples: rowSamples, rowRays: rowRays)
        let inverseWidth = 1 / Float(width)
        let inverseHeight = 1 / Float(height)
        let start = DispatchTime.now().uptimeNanoseconds

        DispatchQueue.concurrentPerform(iterations: height) { y in
            let rowSamples = buffers.rowSamples
            let rowRays = buffers.rowRays
            rowRays[y] = 0
            if let shouldCancel, shouldCancel() { return }
            let sample = Int(rowSamples[y])
            var rng = TracerRNG(seed: seed, row: y, sample: sample)
            var rays: UInt64 = 0
            let row = buffers.accumulation + y * width * 3
            let rowY = Float(y)
            for x in 0..<width {
                let u = (Float(x) + rng.nextFloat()) * inverseWidth
                let v = (rowY + rng.nextFloat()) * inverseHeight
                let lens = rig.hasLens ? Sampling.concentricDisk(rng.nextFloat(), rng.nextFloat()) : SIMD2<Float>.zero
                let ray = rig.ray(x: u, y: v, lens: lens)
                let value = tracer.radiance(origin: ray.origin, direction: ray.direction, rng: &rng, rays: &rays)
                // A NaN or infinity would poison the pixel forever, so drop it.
                if isFinite(value) {
                    let i = x * 3
                    row[i] += value.x
                    row[i + 1] += value.y
                    row[i + 2] += value.z
                }
            }
            rowSamples[y] = Int32(sample + 1)
            rowRays[y] = rays
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9
        var rays: UInt64 = 0
        var minimum = Int.max
        for y in 0..<height {
            rays &+= rowRays[y]
            minimum = min(minimum, Int(rowSamples[y]))
        }

        stateLock.lock()
        completeSamples = minimum
        raysTraced &+= rays
        stateLock.unlock()

        return TracerPassStats(rays: rays, duration: elapsed, completed: minimum > samplesBefore)
    }

    /// The current image as tone-mapped, dithered 8-bit sRGB.
    ///
    /// Pixels are row-major, top row first, 4 bytes each in RGBA order, with
    /// alpha always 255.
    ///
    /// - Parameter exposure: Exposure adjustment in stops.
    public func snapshotRGBA8(exposure: Float = 0) -> [UInt8] {
        passLock.lock()
        defer { passLock.unlock() }

        let width = self.width
        let height = self.height
        let count = width * height * 4
        let scale = TracerToneMapper.exposureScale(exposure)
        let buffers = RowBuffers(accumulation: accumulation, rowSamples: rowSamples, rowRays: rowRays)

        return [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            guard let base = buffer.baseAddress else { return }
            TracerToneMapper.encodingTable.withUnsafeBufferPointer { encodingTable in
                let target = SnapshotTarget(pixels: base, table: encodingTable)
                DispatchQueue.concurrentPerform(iterations: height) { y in
                    let out = target.pixels + y * width * 4
                    let samples = buffers.rowSamples[y]
                    guard samples > 0 else {
                        for x in 0..<width {
                            out[x * 4] = 0
                            out[x * 4 + 1] = 0
                            out[x * 4 + 2] = 0
                            out[x * 4 + 3] = 255
                        }
                        return
                    }
                    TracerToneMapper.encodeRow(buffers.accumulation + y * width * 3, width: width,
                                               scale: scale / Float(samples), y: y, table: target.table, into: out)
                }
            }
            initialized = count
        }
    }

    /// The current image as averaged linear radiance: three floats per pixel,
    /// row-major, top row first.
    public func snapshotLinear() -> [Float] {
        passLock.lock()
        defer { passLock.unlock() }
        var result = [Float](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            let samples = rowSamples[y]
            guard samples > 0 else { continue }
            let factor = 1 / Float(samples)
            let base = y * width * 3
            for i in 0..<(width * 3) {
                result[base + i] = accumulation[base + i] * factor
            }
        }
        return result
    }

    /// What lies under a pixel, at pixel coordinates measured from the top
    /// left. The call doesn't wait for a running pass.
    public func pick(x: Float, y: Float) -> TracerPick? {
        world.pick(camera: camera, x: x / Float(width), y: y / Float(height), aspectRatio: aspectRatio)
    }
}

/// The renderer's buffers, shared with worker threads. Every worker writes
/// only its own row, and the renderer's pass lock keeps passes and snapshots
/// from overlapping, so the sharing is race-free.
private struct RowBuffers: @unchecked Sendable {
    let accumulation: UnsafeMutablePointer<Float>
    let rowSamples: UnsafeMutablePointer<Int32>
    let rowRays: UnsafeMutablePointer<UInt64>
}

/// The snapshot's output pixels and the sRGB lookup table, shared with
/// worker threads that each fill one row.
private struct SnapshotTarget: @unchecked Sendable {
    let pixels: UnsafeMutablePointer<UInt8>
    let table: UnsafeBufferPointer<Float>
}
