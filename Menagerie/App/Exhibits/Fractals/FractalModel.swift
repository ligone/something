import FractalKit
import Observation
import QuartzCore
import SwiftUI

/// Everything the fractal exhibit shows and how it moves. The Metal view
/// feeds input events in, and the renderer asks it each frame what to draw.
@Observable
@MainActor
final class FractalModel {
    // MARK: What to draw

    var kind: FractalKind = .mandelbrot
    var viewport = ComplexViewport.home(for: .mandelbrot, width: 900, height: 640)
    var palette: FractalPalette = .nebula
    /// Multiplies the automatic iteration budget.
    var detail: Double = 1
    /// How quickly colors cycle as escape counts grow.
    var colorDensity: Double = 0.12
    var colorOffset: Double = 0
    var cyclesColors = false
    var showsJuliaPreview = true
    var antialiasing = true

    // MARK: Interaction

    /// The pointer position over the stage, in points.
    private(set) var pointer: CGPoint?
    private(set) var viewSize = CGSize(width: 900, height: 640)
    @ObservationIgnored private var lastInteraction: CFTimeInterval = 0
    @ObservationIgnored private var lastAdvance: CFTimeInterval?
    @ObservationIgnored private var mandelbrotViewport: ComplexViewport?
    @ObservationIgnored private var hasLaidOut = false

    // MARK: Flights and the tour

    private struct Flight {
        let path: ZoomFlight
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let landmark: FractalLandmark?
    }

    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var holdUntil: CFTimeInterval?
    private(set) var isTouring = false
    private(set) var tourIndex = 0
    /// The landmark whose caption is showing.
    private(set) var arrivedLandmark: FractalLandmark?
    /// The landmark currently being flown to.
    private(set) var destination: FractalLandmark?

    // MARK: Stats

    private(set) var gpuMilliseconds: Double = 0
    private(set) var renderedIterations = 0
    private(set) var renderedPrecisely = false
    private(set) var renderedPixels = CGSize.zero
    @ObservationIgnored private var lastStatsUpdate: CFTimeInterval = 0

    /// Below this many complex units per pixel, 32-bit floats can't tell
    /// neighboring pixels apart and the shader switches to double-float.
    static let precisionThreshold = 2e-6

    // MARK: Derived values

    var home: ComplexViewport {
        ComplexViewport.home(for: kind, width: Double(viewSize.width), height: Double(viewSize.height))
    }

    var magnification: Double {
        viewport.magnification(relativeTo: home)
    }

    var iterationBudget: Int {
        EscapeTime.iterationBudget(magnification: magnification, detail: detail)
    }

    var isAnimating: Bool {
        flight != nil || cyclesColors
    }

    /// The complex number under the pointer.
    var pointerValue: (re: Double, im: Double)? {
        guard let pointer else { return nil }
        return viewport.complex(
            atX: Double(pointer.x), y: Double(pointer.y),
            width: Double(viewSize.width), height: Double(viewSize.height)
        )
    }

    /// Where the Julia preview sits, in stage points: the right edge, just
    /// below the HUD, clear of the tour caption and the hint.
    var juliaInsetRect: CGRect {
        let side = min(250, max(150, min(viewSize.width, viewSize.height) * 0.3))
        return CGRect(x: viewSize.width - side - 16, y: 96, width: side, height: side)
    }

    /// The parameter of the Julia set previewed in the inset, if any.
    var juliaPreviewParameter: (re: Double, im: Double)? {
        guard showsJuliaPreview, !kind.isJulia, flight == nil, let pointer, let value = pointerValue else {
            return nil
        }
        guard !juliaInsetRect.insetBy(dx: -8, dy: -8).contains(pointer) else { return frozenJuliaParameter }
        return value
    }

    /// While the pointer is over the inset itself, the preview holds still.
    @ObservationIgnored private var frozenJuliaParameter: (re: Double, im: Double)?

    // MARK: Frame updates

    /// Advances flights, the tour and color cycling. Called once per frame.
    func advance(to now: CFTimeInterval) {
        let dt = lastAdvance.map { min(now - $0, 0.1) } ?? 0
        lastAdvance = now

        if cyclesColors {
            colorOffset = (colorOffset + dt * 0.06).truncatingRemainder(dividingBy: 1)
        }

        if let flight {
            let t = min(max((now - flight.start) / flight.duration, 0), 1)
            let eased = t * t * (3 - 2 * t)
            viewport = flight.path.viewport(at: eased)
            if t >= 1 {
                self.flight = nil
                destination = nil
                arrive(at: flight.landmark, now: now)
            }
        } else if isTouring, let holdUntil, now >= holdUntil {
            self.holdUntil = nil
            advanceTour(now: now)
        }
    }

    /// Whether the renderer should favor speed right now.
    func isInteracting(now: CFTimeInterval) -> Bool {
        flight != nil || now - lastInteraction < 0.2
    }

    func recordFrame(gpuSeconds: Double, iterations: Int, precise: Bool, pixels: CGSize) {
        let now = CACurrentMediaTime()
        // Throttle stats so SwiftUI isn't re-rendered for every frame.
        guard now - lastStatsUpdate > 0.25 || precise != renderedPrecisely else { return }
        lastStatsUpdate = now
        gpuMilliseconds = gpuSeconds * 1000
        renderedIterations = iterations
        renderedPrecisely = precise
        renderedPixels = pixels
    }

    // MARK: Layout

    func layout(size: CGSize) {
        guard size.width > 1, size.height > 1, size != viewSize else { return }
        let oldSize = viewSize
        viewSize = size
        if !hasLaidOut {
            hasLaidOut = true
            viewport = home
            if AppEnvironment.isCaptureTour { showcaseForScreenshots() }
        } else if oldSize.width > 1 {
            // Keep showing the same region when the window resizes.
            let widthRatio = Double(oldSize.width / size.width)
            viewport.scale *= widthRatio
        }
    }

    // MARK: Input

    func pointerMoved(to point: CGPoint?) {
        if let point, juliaInsetRect.insetBy(dx: -8, dy: -8).contains(point) {
            if frozenJuliaParameter == nil { frozenJuliaParameter = pointerValue }
        } else {
            frozenJuliaParameter = nil
        }
        pointer = point
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        interrupt()
        viewport.pan(dx: Double(dx), dy: Double(dy))
    }

    func zoom(by factor: CGFloat, at point: CGPoint) {
        interrupt()
        viewport.zoom(
            by: Double(factor),
            aroundX: Double(point.x), y: Double(point.y),
            width: Double(viewSize.width), height: Double(viewSize.height)
        )
    }

    /// Double-click: glide in 4× toward the point (or out, with Option).
    func dive(at point: CGPoint, outward: Bool) {
        interrupt()
        var target = viewport
        target.zoom(
            by: outward ? 0.25 : 4,
            aroundX: Double(point.x), y: Double(point.y),
            width: Double(viewSize.width), height: Double(viewSize.height)
        )
        fly(to: target, landmark: nil, speed: 2.4)
    }

    /// Option-drag in Julia mode morphs the set by moving its parameter.
    func morphJulia(dx: CGFloat, dy: CGFloat) {
        guard case let .julia(re, im) = kind else { return }
        interrupt()
        let step = 0.0016 * min(1, viewport.scale / home.scale * 4)
        kind = .julia(re: re + Double(dx) * step, im: im - Double(dy) * step)
    }

    func click(at point: CGPoint) {
        guard !kind.isJulia, showsJuliaPreview, juliaInsetRect.contains(point),
              let c = frozenJuliaParameter ?? pointerValue else { return }
        showJulia(re: c.re, im: c.im)
    }

    func keyPressed(_ key: FractalKey) {
        let step = min(viewSize.width, viewSize.height) * 0.12
        switch key {
        case .left: pan(dx: step, dy: 0)
        case .right: pan(dx: -step, dy: 0)
        case .up: pan(dx: 0, dy: step)
        case .down: pan(dx: 0, dy: -step)
        case .zoomIn: zoom(by: 1.5, at: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        case .zoomOut: zoom(by: 1 / 1.5, at: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        case .toggleJulia: toggleJulia()
        case .reset: resetView()
        case .toggleTour: isTouring ? stopTour() : startTour()
        case .escape: stopTour()
        }
    }

    // MARK: Commands

    func resetView() {
        stopTour()
        fly(to: home, landmark: nil, speed: 2.2)
    }

    func toggleJulia() {
        if kind.isJulia {
            showMandelbrot()
        } else {
            let c = juliaPreviewParameter ?? pointerValue ?? (re: -0.8, im: 0.156)
            showJulia(re: c.re, im: c.im)
        }
    }

    func showJulia(re: Double, im: Double) {
        stopTour()
        if !kind.isJulia { mandelbrotViewport = viewport }
        kind = .julia(re: re, im: im)
        viewport = home
        pointer = nil
    }

    func showMandelbrot() {
        guard kind.isJulia else { return }
        stopTour()
        kind = .mandelbrot
        viewport = mandelbrotViewport ?? home
    }

    func fly(to landmark: FractalLandmark) {
        stopTour()
        if kind.isJulia {
            kind = .mandelbrot
            viewport = mandelbrotViewport ?? home
        }
        fly(to: landmark.viewport(viewWidth: Double(viewSize.width)), landmark: landmark, speed: 1.4)
    }

    func startTour() {
        if kind.isJulia {
            kind = .mandelbrot
            viewport = mandelbrotViewport ?? home
        }
        isTouring = true
        tourIndex = 0
        arrivedLandmark = nil
        let first = FractalLandmark.tour[0]
        fly(to: first.viewport(viewWidth: Double(viewSize.width)), landmark: first, speed: 1.1)
    }

    func stopTour() {
        guard isTouring else { return }
        isTouring = false
        holdUntil = nil
        flight = nil
        destination = nil
        arrivedLandmark = nil
    }

    // MARK: Private

    /// Any direct manipulation cancels flights and the tour.
    private func interrupt() {
        lastInteraction = CACurrentMediaTime()
        if isTouring { stopTour() }
        flight = nil
        destination = nil
        arrivedLandmark = nil
    }

    private func fly(to target: ComplexViewport, landmark: FractalLandmark?, speed: Double) {
        let path = ZoomFlight(from: viewport, to: target, viewWidth: Double(max(viewSize.width, 1)), speed: speed)
        flight = Flight(path: path, start: CACurrentMediaTime(), duration: path.duration, landmark: landmark)
        destination = landmark
        arrivedLandmark = nil
    }

    private func arrive(at landmark: FractalLandmark?, now: CFTimeInterval) {
        arrivedLandmark = landmark
        if isTouring {
            holdUntil = now + (landmark == nil ? 0.5 : 6.5)
        }
    }

    private func advanceTour(now: CFTimeInterval) {
        tourIndex += 1
        if tourIndex < FractalLandmark.tour.count {
            let next = FractalLandmark.tour[tourIndex]
            fly(to: next.viewport(viewWidth: Double(viewSize.width)), landmark: next, speed: 1.1)
        } else if arrivedLandmark != nil {
            // Last stop seen: fly home and end.
            arrivedLandmark = nil
            fly(to: home, landmark: nil, speed: 1.6)
        } else {
            isTouring = false
        }
    }

    /// CI screenshot: a deep landmark with the Julia preview showing.
    private func showcaseForScreenshots() {
        let landmark = FractalLandmark.tour[4]
        viewport = landmark.viewport(viewWidth: Double(viewSize.width))
        arrivedLandmark = landmark
        pointer = CGPoint(x: viewSize.width * 0.42, y: viewSize.height * 0.38)
    }
}

enum FractalKey {
    case left, right, up, down, zoomIn, zoomOut, toggleJulia, reset, toggleTour, escape
}
