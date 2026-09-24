import AppKit
import CalculusKit
import Observation
import SwiftUI

/// A draggable marker on the plot.
enum CalculusHandle: Equatable {
    case lowerBound, upperBound, taylorCenter
}

/// The workbench's state: the function being studied, the layers on show,
/// the view onto the plane, and results computed from all of those.
///
/// Parsing and differentiation are fast enough to run on every keystroke.
/// Finding roots and extrema, and integrating, run off the main actor, so a
/// pathological function never stalls the UI.
@MainActor
@Observable
final class CalculusModel {
    // MARK: The function

    private(set) var analysis: FunctionAnalysis
    private(set) var parseError: MathParseError? = nil
    /// Whether to show `parseError`. Errors wait until typing pauses, so a
    /// half-typed `sin(` doesn't flash red.
    private(set) var revealsError = false
    private var storedSource: String

    /// The text in the input field. Setting it re-parses; a valid function
    /// replaces the current one immediately.
    var source: String {
        get { storedSource }
        set {
            guard newValue != storedSource else { return }
            storedSource = newValue
            parseSource(revealingErrors: false)
        }
    }

    // MARK: Layers

    var showsDerivative = true
    var showsSecondDerivative = false
    var showsTaylor = true
    var showsIntegral = true
    var showsFeatures = true

    // MARK: Taylor polynomial

    /// The polynomial's order, 0 through ``maximumTaylorOrder``.
    private(set) var taylorOrder: Int
    var taylorCenter: Double
    private(set) var isSweepingTaylorOrder = false
    static let maximumTaylorOrder = 12

    // MARK: Integral

    private var storedLowerBound: Double
    private var storedUpperBound: Double
    private(set) var integral: IntegralResult? = nil
    /// True while a new integral is being computed.
    private(set) var integralIsUpdating = false

    var lowerBound: Double {
        get { storedLowerBound }
        set {
            storedLowerBound = newValue
            scheduleIntegral()
        }
    }

    var upperBound: Double {
        get { storedUpperBound }
        set {
            storedUpperBound = newValue
            scheduleIntegral()
        }
    }

    // MARK: The view

    private(set) var viewport = CalculusViewport(centerX: 0, centerY: 0, unitsPerPointX: 0.025, unitsPerPointY: 0.025)
    private(set) var plotSize = CGSize.zero
    /// Roots, extrema and inflection points in and around the view.
    private(set) var features = CurveFeatures(interval: 0...0)
    /// Where the pointer is over the plot, if it is.
    var hoverLocation: CGPoint? = nil
    /// The handle being dragged.
    private(set) var draggedHandle: CalculusHandle? = nil
    private(set) var isPanning = false
    private(set) var example: CalculusExample

    // MARK: Private state

    @ObservationIgnored private var panStart: CalculusViewport? = nil
    @ObservationIgnored private var featureTask: Task<Void, Never>? = nil
    @ObservationIgnored private var integralTask: Task<Void, Never>? = nil
    @ObservationIgnored private var errorTask: Task<Void, Never>? = nil
    @ObservationIgnored private var sweepTask: Task<Void, Never>? = nil
    @ObservationIgnored private var taylorMemo: (function: MathExpr, center: Double, series: TaylorSeries)? = nil
    @ObservationIgnored private var hasAppeared = false

    init() {
        let example = CalculusExample.opening
        self.example = example
        storedSource = example.source
        // The opening source is a known-good literal, so this never falls back.
        analysis = (try? FunctionAnalysis(parsing: example.source)) ?? FunctionAnalysis(.variable)
        taylorOrder = example.taylorOrder
        taylorCenter = example.taylorCenter
        storedLowerBound = example.integralBounds.lowerBound
        storedUpperBound = example.integralBounds.upperBound
    }

    // MARK: Lifecycle

    func appear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        scheduleIntegral()
        // Build the Taylor polynomial up term by term, the exhibit's
        // signature moment.
        sweepTaylorOrder(from: 1, to: example.taylorOrder, step: .milliseconds(AppEnvironment.isCaptureTour ? 120 : 190))
    }

    /// Cancels all background work. Called when the exhibit goes away.
    func stop() {
        featureTask?.cancel()
        integralTask?.cancel()
        errorTask?.cancel()
        sweepTask?.cancel()
        isSweepingTaylorOrder = false
    }

    // MARK: Editing the function

    /// Enter pressed: show any error right away.
    func commitSource() {
        parseSource(revealingErrors: true)
    }

    /// Loads one of the curated examples, with its framing and settings.
    func choose(_ example: CalculusExample) {
        self.example = example
        storedSource = example.source
        parseSource(revealingErrors: true)
        taylorCenter = example.taylorCenter
        storedLowerBound = example.integralBounds.lowerBound
        storedUpperBound = example.integralBounds.upperBound
        scheduleIntegral()
        if plotSize.width > 0 {
            setViewport(example.viewport(in: plotSize), featureDelay: .zero)
        }
        sweepTaylorOrder(from: 0, to: example.taylorOrder, step: .milliseconds(150))
    }

    private func parseSource(revealingErrors: Bool) {
        errorTask?.cancel()
        do {
            let parsed = try FunctionAnalysis(parsing: storedSource)
            parseError = nil
            revealsError = false
            guard parsed.function != analysis.function else { return }
            analysis = parsed
            scheduleFeatures(delay: .zero)
            scheduleIntegral()
        } catch {
            parseError = error as? MathParseError
                ?? MathParseError("That isn't a function of x", position: 0)
            if revealingErrors {
                revealsError = true
            } else {
                revealsError = false
                errorTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !Task.isCancelled else { return }
                    self?.revealsError = true
                }
            }
        }
    }

    // MARK: Taylor polynomial

    func setTaylorOrder(_ order: Int) {
        sweepTask?.cancel()
        isSweepingTaylorOrder = false
        taylorOrder = min(max(order, 0), Self.maximumTaylorOrder)
    }

    /// Plays the order from 0 to 12, or stops a sweep in progress.
    func toggleTaylorSweep() {
        if isSweepingTaylorOrder {
            setTaylorOrder(taylorOrder)
        } else {
            showsTaylor = true
            sweepTaylorOrder(from: 0, to: Self.maximumTaylorOrder, step: .milliseconds(420))
        }
    }

    private func sweepTaylorOrder(from start: Int, to end: Int, step: Duration) {
        sweepTask?.cancel()
        isSweepingTaylorOrder = true
        taylorOrder = start
        sweepTask = Task { [weak self] in
            var order = start
            while order != end {
                try? await Task.sleep(for: step)
                guard !Task.isCancelled, let self else { return }
                order += order < end ? 1 : -1
                self.taylorOrder = order
            }
            self?.isSweepingTaylorOrder = false
        }
    }

    /// The Taylor series through order 12 at the current center.
    var taylorSeries: TaylorSeries {
        let function = analysis.function
        let center = taylorCenter
        if let memo = taylorMemo, memo.center == center, memo.function == function {
            return memo.series
        }
        let series = analysis.taylorSeries(at: center, order: Self.maximumTaylorOrder)
        taylorMemo = (function, center, series)
        return series
    }

    // MARK: Integral

    private func scheduleIntegral() {
        integralTask?.cancel()
        let analysis = analysis
        let lower = storedLowerBound
        let upper = storedUpperBound
        integralIsUpdating = true
        integralTask = Task { [weak self] in
            // Let a dragged slider settle a moment between computations.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                analysis.integral(from: lower, to: upper)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.integral = result
            self.integralIsUpdating = false
        }
    }

    // MARK: The view

    /// Called with the plot's size whenever it changes.
    func setPlotSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1, size != plotSize else { return }
        let isFirstLayout = plotSize.width <= 1
        plotSize = size
        if isFirstLayout {
            setViewport(example.viewport(in: size), featureDelay: .zero)
            if AppEnvironment.isCaptureTour {
                // Hold the pointer still over a slope, so the screenshot
                // shows the tangent line.
                let x = 2.35
                hoverLocation = CGPoint(
                    x: viewport.screenX(x, in: size),
                    y: viewport.screenY(analysis.f(x), in: size)
                )
            }
        } else {
            scheduleFeatures(delay: .milliseconds(60))
        }
    }

    /// The features inside the visible x-range.
    var visibleFeatures: CurveFeatures {
        guard plotSize.width > 0 else { return features }
        let range = viewport.xRange(in: plotSize)
        return CurveFeatures(
            interval: range,
            roots: features.roots.filter { range.contains($0) },
            extrema: features.extrema.filter { range.contains($0.x) },
            inflectionPoints: features.inflectionPoints.filter { range.contains($0.x) }
        )
    }

    /// Frames the current example, or the default window for a function
    /// typed by hand.
    func resetView() {
        guard plotSize.width > 0 else { return }
        let framing = storedSource == example.source ? example : CalculusExample.opening
        setViewport(framing.viewport(in: plotSize), featureDelay: .zero)
    }

    /// Zooms around the pointer. With ⌥ only y stretches; with ⌘ only x.
    func zoom(by factor: Double, around anchor: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard plotSize.width > 0 else { return }
        var zoomed = viewport
        let onlyY = modifiers.contains(.option)
        let onlyX = modifiers.contains(.command)
        zoomed.zoom(by: factor, around: anchor, in: plotSize, horizontally: !onlyY, vertically: !onlyX)
        setViewport(zoomed, featureDelay: .milliseconds(80))
    }

    func zoom(by factor: Double) {
        let middle = CGPoint(x: plotSize.width / 2, y: plotSize.height / 2)
        zoom(by: factor, around: middle, modifiers: [])
    }

    private func setViewport(_ newViewport: CalculusViewport, featureDelay: Duration) {
        viewport = newViewport
        scheduleFeatures(delay: featureDelay)
    }

    /// Finds features across the view and half a screen either side, so
    /// panning reveals markers that are already there.
    private func scheduleFeatures(delay: Duration) {
        guard plotSize.width > 0 else { return }
        featureTask?.cancel()
        let analysis = analysis
        let visible = viewport.xRange(in: plotSize)
        let margin = 0.5 * (visible.upperBound - visible.lowerBound)
        let window = (visible.lowerBound - margin)...(visible.upperBound + margin)
        featureTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            let features = await Task.detached(priority: .userInitiated) {
                analysis.features(in: window, samples: 3000, limit: 80)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.features = features
        }
    }

    // MARK: Dragging

    func dragChanged(start: CGPoint, location: CGPoint, translation: CGSize) {
        if draggedHandle == nil, panStart == nil {
            if let handle = handle(at: start) {
                draggedHandle = handle
            } else {
                panStart = viewport
                isPanning = true
            }
        }
        if let handle = draggedHandle {
            let x = viewport.plotX(location.x, in: plotSize)
            move(handle, to: x)
        } else if let panStart {
            setViewport(panStart.panned(by: translation), featureDelay: .milliseconds(60))
        }
    }

    func dragEnded() {
        draggedHandle = nil
        panStart = nil
        isPanning = false
    }

    private func move(_ handle: CalculusHandle, to x: Double) {
        // Snap to the grid's minor lines when close, so round numbers are
        // easy to hit. The spacing matches PlotPainter.drawGrid.
        let width = Double(plotSize.width)
        let step = AxisTicks.step(span: viewport.unitsPerPointX * width, targetCount: max(2, width / 110))
        let minor = step / Double(AxisTicks.minorDivisions(for: step))
        let snapped = (x / minor).rounded() * minor
        let value = abs(snapped - x) < 4 * viewport.unitsPerPointX ? snapped : x
        switch handle {
        case .lowerBound: lowerBound = value
        case .upperBound: upperBound = value
        case .taylorCenter: taylorCenter = value
        }
    }

    // MARK: Handles

    /// The handles on show.
    var visibleHandles: [CalculusHandle] {
        var handles: [CalculusHandle] = []
        if showsIntegral { handles += [.lowerBound, .upperBound] }
        if showsTaylor { handles.append(.taylorCenter) }
        return handles
    }

    func value(of handle: CalculusHandle) -> Double {
        switch handle {
        case .lowerBound: storedLowerBound
        case .upperBound: storedUpperBound
        case .taylorCenter: taylorCenter
        }
    }

    /// Where a handle's knob sits: on the x-axis, or pinned to the nearest
    /// edge when the axis is off screen. Integral knobs sit just below the
    /// axis and the Taylor knob just above, so they never cover each other.
    func knobCenter(for handle: CalculusHandle) -> CGPoint {
        let axis = viewport.screenY(0, in: plotSize)
        let rail = min(max(axis, 34), max(34, plotSize.height - 64))
        let x = viewport.screenX(value(of: handle), in: plotSize)
        let offset: CGFloat = handle == .taylorCenter ? -15 : 15
        return CGPoint(x: x, y: rail + offset)
    }

    /// The handle under `point`, if any: its knob, anywhere along an
    /// integral bound's dashed line, or the Taylor center's ring on the curve.
    func handle(at point: CGPoint) -> CalculusHandle? {
        guard plotSize.width > 0 else { return nil }
        var best: CalculusHandle?
        var bestDistance = CGFloat.infinity
        for handle in visibleHandles {
            let knob = knobCenter(for: handle)
            let dx = abs(point.x - knob.x)
            let dy = abs(point.y - knob.y)
            let onKnob = dx <= 16 && dy <= 13
            let onGuide: Bool
            if handle == .taylorCenter {
                let ringY = viewport.screenY(analysis.f(taylorCenter), in: plotSize)
                onGuide = dx <= 10 && abs(point.y - ringY) <= 10
            } else {
                onGuide = dx <= 5
            }
            guard onKnob || onGuide else { continue }
            // Knobs win over guide lines.
            let distance = onKnob ? dx * 0.5 : dx + 8
            if distance < bestDistance {
                best = handle
                bestDistance = distance
            }
        }
        return best
    }
}
