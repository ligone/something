import Observation
import SwiftUI
import TracerKit

/// Render resolution presets, as render pixels per stage point.
enum PathTracerQuality: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case crisp

    var id: Self { self }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .crisp: return "Crisp"
        }
    }

    var scale: Double {
        switch self {
        case .fast: return 0.35
        case .balanced: return 0.6
        case .crisp: return 1.0
        }
    }
}

/// Tuning constants for the exhibit.
enum PathTracerTuning {
    /// Samples per pixel at which the image counts as converged and rendering
    /// stops.
    static let targetSamples = 4096
    static let maxFramesPerSecond = 30.0
    /// Orbit speed for mouse drags.
    static let orbitRadiansPerPoint: Float = 0.0055
    /// Upper bounds on the render resolution, whatever the stage size.
    static let maxRenderWidth = 1600.0
    static let maxRenderHeight = 1000.0
    /// Delay before a resized stage rebuilds the renderer.
    static let resizeDebounce = Duration.milliseconds(180)
    /// Time a scroll or pinch keeps the fast preview resolution alive after
    /// its last event.
    static let scrollSettle = Duration.milliseconds(220)
}

/// The latest numbers from the renderer, for the HUD and the panel.
struct PathTracerStats: Equatable {
    var samples = 0
    var targetSamples = PathTracerTuning.targetSamples
    var raysPerSecond = 0.0
    var elapsed = 0.0
    var width = 0
    var height = 0
    var state: TracerSession.State = .rendering

    var progress: Double {
        guard targetSamples > 0 else { return 0 }
        return min(1, Double(samples) / Double(targetSamples))
    }
}

/// A focus confirmation drawn where the user clicked.
struct PathTracerFocusMark: Identifiable, Equatable {
    let id: Int
    let location: CGPoint
    let caption: String
}

/// A rendered frame, carried from the render thread to the main actor.
private struct PathTracerFrameDelivery: @unchecked Sendable {
    let frame: TracerSession.Frame
    let image: CGImage?
}

/// Drives the Path Tracer exhibit. It owns the background `TracerSession`,
/// turns gestures and control changes into render configurations, and
/// publishes finished frames for display.
///
/// Everything here runs on the main actor. Rendering happens on the
/// session's own thread, and frames come back through `present(_:)`.
@MainActor
@Observable
final class PathTracerModel {
    // MARK: Scene and settings

    private(set) var preset: TracerScenePreset
    private(set) var world: TracerWorld
    private(set) var aperture: Double
    private(set) var focusDistance: Double
    private(set) var maxBounces: Double
    private(set) var exposure: Double
    private(set) var quality: PathTracerQuality = .balanced
    private(set) var isPaused = false

    // MARK: Output

    private(set) var image: CGImage?
    private(set) var stats = PathTracerStats()
    private(set) var focusMark: PathTracerFocusMark?
    /// These change rarely, so views that only need them don't redraw with
    /// every frame.
    private(set) var hasImage = false
    private(set) var isConverged = false

    // MARK: Private state

    @ObservationIgnored private var orbit: TracerOrbit
    @ObservationIgnored private var session: TracerSession?
    @ObservationIgnored private var stageSize: CGSize = .zero
    @ObservationIgnored private var isInteracting = false
    @ObservationIgnored private var dragOrigin: TracerOrbit?
    @ObservationIgnored private var gestureStart: CGPoint?
    @ObservationIgnored private var resizeTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var focusMarkTask: Task<Void, Never>?
    @ObservationIgnored private var focusMarkSerial = 0

    /// Cheap and free of side effects. Rendering begins in `start()`.
    init(preset: TracerScenePreset = .cornellBox) {
        let scene = preset.makeScene()
        self.preset = preset
        self.world = TracerWorld(scene: scene)
        self.orbit = TracerOrbit(camera: scene.camera)
        self.aperture = Double(scene.camera.aperture)
        self.focusDistance = Double(scene.camera.focusDistance)
        self.maxBounces = Double(scene.maxBounces)
        self.exposure = Double(scene.exposure)
    }

    // MARK: Slider ranges

    /// The aperture slider's upper end, scaled to the scene's default lens.
    var apertureLimit: Double {
        max(0.2, Double(world.scene.camera.aperture) * 4)
    }

    /// The focus slider's range in world units, wide enough to reach from the
    /// lens to beyond the farthest orbit.
    var focusRange: ClosedRange<Double> {
        0.25...max(20, Double(world.scene.orbitLimits.distance.upperBound) * 2.5)
    }

    // MARK: Lifecycle

    func start() {
        guard session == nil else { return }
        let session = TracerSession(targetSamples: PathTracerTuning.targetSamples,
                                    maxFramesPerSecond: PathTracerTuning.maxFramesPerSecond,
                                    exposure: Float(exposure)) { [weak self] frame in
            // This runs on the render thread. Build the image here, off the
            // main thread, then hand it over.
            let image = PixelImage.make(width: frame.width, height: frame.height, rgba: frame.pixels)
            let delivery = PathTracerFrameDelivery(frame: frame, image: image)
            Task { @MainActor [weak self] in
                self?.present(delivery)
            }
        }
        session.setPaused(isPaused)
        self.session = session
        submit()
    }

    /// Ends the render thread and every pending task. Call it when the
    /// exhibit leaves the screen.
    func stop() {
        session?.stop()
        session = nil
        resizeTask?.cancel()
        settleTask?.cancel()
        focusMarkTask?.cancel()
        resizeTask = nil
        settleTask = nil
        focusMarkTask = nil
        dragOrigin = nil
        gestureStart = nil
        isInteracting = false
        focusMark = nil
    }

    private func present(_ delivery: PathTracerFrameDelivery) {
        guard session != nil else { return }
        if let image = delivery.image {
            self.image = image
            if !hasImage { hasImage = true }
        }
        let frame = delivery.frame
        stats = PathTracerStats(samples: frame.samplesPerPixel, targetSamples: frame.targetSamples,
                                raysPerSecond: frame.raysPerSecond, elapsed: frame.elapsed,
                                width: frame.width, height: frame.height, state: frame.state)
        let converged = frame.state == .converged
        if converged != isConverged { isConverged = converged }
    }

    // MARK: Stage size

    /// Tracks the stage size. The first size applies at once, so the first
    /// frame arrives quickly. Later changes are debounced while a window
    /// resize is in progress, and the old image stretches to fill meanwhile.
    func stageResized(to size: CGSize) {
        guard size.width >= 2, size.height >= 2 else { return }
        resizeTask?.cancel()
        if stageSize == .zero {
            stageSize = size
            submit()
            return
        }
        guard size != stageSize else { return }
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: PathTracerTuning.resizeDebounce)
            guard !Task.isCancelled, let self else { return }
            self.stageSize = size
            self.submit()
        }
    }

    // MARK: Gestures

    /// Called throughout a drag. The drag becomes an orbit after a few points
    /// of movement, and until then it may still end as a click.
    func dragChanged(start: CGPoint, translation: CGSize) {
        if start != gestureStart {
            // A new press. Drop any drag that ended without `dragEnded`, for
            // example one interrupted by a system alert.
            gestureStart = start
            if dragOrigin != nil {
                dragOrigin = nil
                setInteracting(false)
            }
        }
        if dragOrigin == nil {
            let distance = (translation.width * translation.width + translation.height * translation.height).squareRoot()
            guard distance >= 3 else { return }
            dragOrigin = orbit
            setInteracting(true)
        }
        guard let origin = dragOrigin else { return }
        var next = origin
        next.yaw = origin.yaw - Float(translation.width) * PathTracerTuning.orbitRadiansPerPoint
        next.pitch = origin.pitch + Float(translation.height) * PathTracerTuning.orbitRadiansPerPoint
        orbit = next.clamped(to: world.scene.orbitLimits)
        resumeIfPaused()
        submit()
    }

    /// Ends an orbit, or treats a motionless press as a click: one click
    /// focuses, and a double-click resets the camera.
    func dragEnded(at location: CGPoint, clickCount: Int) {
        gestureStart = nil
        if dragOrigin != nil {
            dragOrigin = nil
            setInteracting(false)
        } else if clickCount >= 2 {
            resetCamera()
        } else {
            focus(at: location)
        }
    }

    /// Scroll or pinch. A factor above 1 moves closer. The focus plane moves
    /// along with the camera, so whatever was sharp stays sharp.
    func dolly(zoomFactor: Double) {
        guard zoomFactor.isFinite, zoomFactor > 0, abs(zoomFactor - 1) > 1e-4 else { return }
        let before = orbit.distance
        var next = orbit
        next.distance = before / Float(zoomFactor)
        next = next.clamped(to: world.scene.orbitLimits)
        guard next.distance != before else { return }
        orbit = next
        let shifted = focusDistance + Double(next.distance - before)
        focusDistance = min(max(shifted, focusRange.lowerBound), focusRange.upperBound)

        setInteracting(true)
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: PathTracerTuning.scrollSettle)
            guard !Task.isCancelled, let self, self.dragOrigin == nil else { return }
            self.setInteracting(false)
        }
        resumeIfPaused()
        submit()
    }

    /// Click to focus: cast a ray through the clicked point and put the plane
    /// of focus at whatever it hits. Clicking the sky focuses at infinity.
    func focus(at location: CGPoint) {
        guard stageSize.width >= 2, stageSize.height >= 2 else { return }
        let aspect = renderAspectRatio
        let x = Float(location.x / stageSize.width)
        let y = Float(location.y / stageSize.height)
        let caption: String
        if let pick = world.pick(camera: camera(aspectRatio: aspect), x: x, y: y, aspectRatio: aspect) {
            focusDistance = min(max(Double(pick.focusDistance), focusRange.lowerBound), focusRange.upperBound)
            let name = pick.objectName.isEmpty ? "Focus" : pick.objectName
            caption = "\(name) · \(String(format: "%.2f", focusDistance))"
        } else {
            focusDistance = focusRange.upperBound
            caption = "Infinity"
        }
        // A pinhole has no depth of field, so focusing would change nothing.
        // Open the lens to the scene's default so the click shows a result.
        if aperture == 0 {
            aperture = Double(world.scene.camera.aperture)
        }
        showFocusMark(at: location, caption: caption)
        resumeIfPaused()
        submit()
    }

    func resetCamera() {
        let scene = world.scene
        orbit = TracerOrbit(camera: scene.camera)
        aperture = Double(scene.camera.aperture)
        focusDistance = Double(scene.camera.focusDistance)
        // The first click of a double-click has just shown a focus mark that
        // no longer applies.
        focusMarkTask?.cancel()
        focusMark = nil
        resumeIfPaused()
        submit()
    }

    // MARK: Controls

    func select(_ newPreset: TracerScenePreset) {
        guard newPreset != preset else { return }
        let scene = newPreset.makeScene()
        preset = newPreset
        world = TracerWorld(scene: scene)
        orbit = TracerOrbit(camera: scene.camera)
        aperture = Double(scene.camera.aperture)
        focusDistance = Double(scene.camera.focusDistance)
        maxBounces = Double(scene.maxBounces)
        exposure = Double(scene.exposure)
        session?.setExposure(Float(exposure))
        focusMark = nil
        resumeIfPaused()
        submit()
    }

    func setAperture(_ value: Double) {
        aperture = min(max(value, 0), apertureLimit)
        resumeIfPaused()
        submit()
    }

    func setFocusDistance(_ value: Double) {
        focusDistance = min(max(value, focusRange.lowerBound), focusRange.upperBound)
        resumeIfPaused()
        submit()
    }

    func setMaxBounces(_ value: Double) {
        maxBounces = min(max(value.rounded(), 1), 32)
        resumeIfPaused()
        submit()
    }

    /// Exposure only changes tone mapping, so the session republishes the
    /// current image without restarting accumulation.
    func setExposure(_ value: Double) {
        exposure = min(max(value, -3), 3)
        session?.setExposure(Float(exposure))
    }

    func setQuality(_ value: PathTracerQuality) {
        guard value != quality else { return }
        quality = value
        resumeIfPaused()
        submit()
    }

    func togglePause() {
        isPaused.toggle()
        session?.setPaused(isPaused)
    }

    func restart() {
        resumeIfPaused()
        session?.restart()
    }

    func savePNG() {
        guard let image else { return }
        let name = "\(preset.title) \(stats.samples) spp.png"
        PathTracerExport.presentSavePanel(for: image, suggestedName: name)
    }

    // MARK: Configuration

    private var renderSize: (width: Int, height: Int) {
        var scale = quality.scale
        if isInteracting {
            // Previews render about a quarter of the pixels, so dragging
            // stays fluid on any Mac.
            scale = max(scale * 0.5, 0.15)
        }
        var width = Double(stageSize.width) * scale
        var height = Double(stageSize.height) * scale
        let fit = min(1, PathTracerTuning.maxRenderWidth / width, PathTracerTuning.maxRenderHeight / height)
        width *= fit
        height *= fit
        return (max(Int(width.rounded()), 8), max(Int(height.rounded()), 8))
    }

    private var renderAspectRatio: Float {
        let size = renderSize
        return Float(size.width) / Float(size.height)
    }

    private func camera(aspectRatio: Float) -> TracerCamera {
        var lens = world.scene.camera
        lens.aperture = Float(aperture)
        lens.focusDistance = Float(focusDistance)
        return orbit.camera(lens: lens)
            .framed(forAspectRatio: aspectRatio, referenceAspectRatio: world.scene.referenceAspectRatio)
    }

    /// Sends the current state to the render thread. Unchanged configurations
    /// are ignored there, so calling this often is cheap.
    private func submit() {
        guard let session, stageSize.width >= 2, stageSize.height >= 2 else { return }
        let size = renderSize
        let aspect = Float(size.width) / Float(size.height)
        let settings = TracerRenderSettings(maxBounces: Int(maxBounces.rounded()))
        session.submit(TracerSession.Configuration(world: world, camera: camera(aspectRatio: aspect),
                                                   width: size.width, height: size.height, settings: settings))
    }

    private func setInteracting(_ value: Bool) {
        guard isInteracting != value else { return }
        isInteracting = value
        submit()
    }

    private func resumeIfPaused() {
        guard isPaused else { return }
        isPaused = false
        session?.setPaused(false)
    }

    private func showFocusMark(at location: CGPoint, caption: String) {
        focusMarkSerial += 1
        let mark = PathTracerFocusMark(id: focusMarkSerial, location: location, caption: caption)
        focusMark = mark
        focusMarkTask?.cancel()
        focusMarkTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled, let self, self.focusMark?.id == mark.id else { return }
            self.focusMark = nil
        }
    }
}
