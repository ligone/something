import CalculusKit
import SwiftUI

/// Colors for the plot, tuned for the dark stage.
enum CalculusPalette {
    static let function = Color(red: 0.40, green: 0.68, blue: 1.00)
    static let derivative = Color(red: 1.00, green: 0.63, blue: 0.28)
    static let secondDerivative = Color(red: 0.95, green: 0.45, blue: 0.80)
    static let taylor = Color(red: 0.38, green: 0.93, blue: 0.64)
    static let positiveArea = Color(red: 0.40, green: 0.68, blue: 1.00)
    static let negativeArea = Color(red: 1.00, green: 0.44, blue: 0.42)
    static let root = Color.white
    static let extremum = Color(red: 1.00, green: 0.84, blue: 0.34)
    static let inflection = Color(red: 0.76, green: 0.58, blue: 1.00)
    static let error = Color(red: 1.00, green: 0.45, blue: 0.42)
}

/// Converts between plot coordinates and a canvas of a given size.
struct CalculusPlotGeometry {
    let viewport: CalculusViewport
    let size: CGSize

    var xRange: ClosedRange<Double> { viewport.xRange(in: size) }
    var yRange: ClosedRange<Double> { viewport.yRange(in: size) }

    func screenX(_ x: Double) -> CGFloat {
        viewport.screenX(x, in: size)
    }

    /// Screen y, clamped to a few screens beyond the edges: Core Graphics
    /// loses precision with astronomically distant points, and nothing out
    /// there is visible anyway.
    func screenY(_ y: Double) -> CGFloat {
        let raw = viewport.screenY(y, in: size)
        let limit = 4 * size.height
        guard raw.isFinite else { return y > 0 ? -limit : limit }
        return min(max(raw, -limit), size.height + limit)
    }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: screenX(x), y: screenY(y))
    }

    func point(_ plotPoint: PlotPoint) -> CGPoint {
        point(plotPoint.x, plotPoint.y)
    }

    func isVisible(_ point: CGPoint, margin: CGFloat = 10) -> Bool {
        point.x >= -margin && point.x <= size.width + margin && point.y >= -margin && point.y <= size.height + margin
    }

    /// Samples `f` at about one point per point of width, split wherever the
    /// curve must not be joined.
    func polylines(_ f: (Double) -> Double, over domain: ClosedRange<Double>? = nil) -> [[PlotPoint]] {
        let span = domain ?? xRange
        let width = screenX(span.upperBound) - screenX(span.lowerBound)
        let count = width.isFinite ? min(4000, max(8, Int(width.rounded()))) : 8
        return CurveSampler.polylines(of: f, over: span, count: count, visibleRange: yRange)
    }

    func path(_ polylines: [[PlotPoint]]) -> Path {
        var path = Path()
        for line in polylines {
            guard let first = line.first else { continue }
            path.move(to: point(first))
            for plotPoint in line.dropFirst() {
                path.addLine(to: point(plotPoint))
            }
        }
        return path
    }

    /// Nudges a coordinate to the middle of a pixel row, so 1-point lines
    /// stay crisp.
    static func crisp(_ value: CGFloat) -> CGFloat {
        (value - 0.5).rounded() + 0.5
    }
}

/// The static layers of the plot: grid, area, curves and markers. It redraws
/// when the function, the view or a layer changes, but not when the pointer
/// moves; ``CalculusPlotOverlay`` handles that.
struct CalculusPlotCanvas: View {
    let model: CalculusModel

    var body: some View {
        // Read everything up front, so SwiftUI tracks it for this view.
        let viewport = model.viewport
        let analysis = model.analysis
        let showsDerivative = model.showsDerivative
        let showsSecondDerivative = model.showsSecondDerivative
        let taylorSeries: TaylorSeries? = model.showsTaylor ? model.taylorSeries : nil
        let taylorOrder = model.taylorOrder
        let area: ClosedRange<Double>? = model.showsIntegral
            ? min(model.lowerBound, model.upperBound)...max(model.lowerBound, model.upperBound)
            : nil
        let features: CurveFeatures? = model.showsFeatures ? model.features : nil

        Canvas { context, size in
            let geometry = CalculusPlotGeometry(viewport: viewport, size: size)
            let f = analysis.f
            PlotPainter.drawGrid(in: &context, geometry)

            if let area {
                PlotPainter.drawArea(in: &context, geometry, f: f, bounds: area)
            }
            // Derivatives only exist where f does: 1/x is no derivative of
            // ln(x) for x < 0.
            if showsSecondDerivative {
                let fDoublePrime = analysis.fDoublePrime
                let curve = geometry.path(geometry.polylines { x in f(x).isFinite ? fDoublePrime(x) : .nan })
                PlotPainter.stroke(curve, in: &context, color: CalculusPalette.secondDerivative.opacity(0.9), width: 1.7)
            }
            if showsDerivative {
                let fPrime = analysis.fPrime
                let curve = geometry.path(geometry.polylines { x in f(x).isFinite ? fPrime(x) : .nan })
                PlotPainter.stroke(curve, in: &context, color: CalculusPalette.derivative.opacity(0.92), width: 1.8)
            }

            let function = geometry.path(geometry.polylines { f($0) })
            PlotPainter.stroke(function, in: &context, color: CalculusPalette.function, width: 2.6, glows: true)

            // Over f, so the dashes visibly ride along the curve where the
            // polynomial agrees with it, then peel away.
            if let taylorSeries, taylorSeries.isDefined(through: taylorOrder) {
                let curve = geometry.path(geometry.polylines { taylorSeries.evaluate(at: $0, order: taylorOrder) })
                PlotPainter.stroke(curve, in: &context, color: CalculusPalette.taylor, width: 2.2, dash: [8, 6])
            }

            if let features {
                PlotPainter.drawFeatures(in: &context, geometry, features)
            }
        }
    }
}

extension CalculusPlotCanvas {
    /// The drawing routines for the plot's static layers.
    fileprivate enum PlotPainter {
        static let labelFont = Font.system(size: 10, weight: .medium, design: .monospaced)

        static func stroke(
            _ path: Path,
            in context: inout GraphicsContext,
            color: Color,
            width: CGFloat,
            dash: [CGFloat] = [],
            glows: Bool = false
        ) {
            if glows {
                let halo = StrokeStyle(lineWidth: width * 3.4, lineCap: .round, lineJoin: .round)
                context.stroke(path, with: .color(color.opacity(0.2)), style: halo)
            }
            let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
            context.stroke(path, with: .color(color), style: style)
        }

        // MARK: Grid

        /// Minor and major grid lines at 1-2-5 spacings, the axes, and labels
        /// that stay on screen when an axis scrolls away.
        static func drawGrid(in context: inout GraphicsContext, _ geometry: CalculusPlotGeometry) {
            let size = geometry.size
            let xRange = geometry.xRange
            let yRange = geometry.yRange
            let xStep = AxisTicks.step(span: xRange.upperBound - xRange.lowerBound, targetCount: max(2, Double(size.width) / 110))
            let yStep = AxisTicks.step(span: yRange.upperBound - yRange.lowerBound, targetCount: max(2, Double(size.height) / 90))
            let xMinor = xStep / Double(AxisTicks.minorDivisions(for: xStep))
            let yMinor = yStep / Double(AxisTicks.minorDivisions(for: yStep))

            func verticals(step: Double) -> Path {
                var path = Path()
                for x in AxisTicks.values(in: xRange, step: step) {
                    let screenX = CalculusPlotGeometry.crisp(geometry.screenX(x))
                    path.move(to: CGPoint(x: screenX, y: 0))
                    path.addLine(to: CGPoint(x: screenX, y: size.height))
                }
                return path
            }
            func horizontals(step: Double) -> Path {
                var path = Path()
                for y in AxisTicks.values(in: yRange, step: step) {
                    let screenY = CalculusPlotGeometry.crisp(geometry.screenY(y))
                    path.move(to: CGPoint(x: 0, y: screenY))
                    path.addLine(to: CGPoint(x: size.width, y: screenY))
                }
                return path
            }

            var minor = verticals(step: xMinor)
            minor.addPath(horizontals(step: yMinor))
            context.stroke(minor, with: .color(.white.opacity(0.035)), lineWidth: 1)
            var major = verticals(step: xStep)
            major.addPath(horizontals(step: yStep))
            context.stroke(major, with: .color(.white.opacity(0.085)), lineWidth: 1)

            // Axes.
            let originX = geometry.screenX(0)
            let originY = geometry.viewport.screenY(0, in: size)
            let yAxisVisible = originX >= 0 && originX <= size.width
            let xAxisVisible = originY >= 0 && originY <= size.height
            var axes = Path()
            if xAxisVisible {
                let y = CalculusPlotGeometry.crisp(originY)
                axes.move(to: CGPoint(x: 0, y: y))
                axes.addLine(to: CGPoint(x: size.width, y: y))
            }
            if yAxisVisible {
                let x = CalculusPlotGeometry.crisp(originX)
                axes.move(to: CGPoint(x: x, y: 0))
                axes.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(axes, with: .color(.white.opacity(0.36)), lineWidth: 1)

            // Tick labels, pinned to the edges when an axis is off screen.
            let labelColor = Color.white.opacity(0.48)
            let labelsBelow = originY < size.height - 22
            let xLabelY = labelsBelow ? max(originY, 0) + 5 : min(originY, size.height) - 5
            let xLabelAnchor: UnitPoint = labelsBelow ? .top : .bottom
            for x in AxisTicks.values(in: xRange, step: xStep) where x != 0 {
                let screenX = geometry.screenX(x)
                guard screenX > 16, screenX < size.width - 16 else { continue }
                let text = Text(AxisTicks.label(x, step: xStep)).font(labelFont).foregroundStyle(labelColor)
                context.draw(text, at: CGPoint(x: screenX, y: xLabelY), anchor: xLabelAnchor)
            }

            let labelsLeft = originX > 44
            let yLabelX = labelsLeft ? min(originX, size.width) - 6 : max(originX, 0) + 6
            let yLabelAnchor: UnitPoint = labelsLeft ? .trailing : .leading
            for y in AxisTicks.values(in: yRange, step: yStep) where y != 0 {
                let screenY = geometry.viewport.screenY(y, in: size)
                guard screenY > 14, screenY < size.height - 14 else { continue }
                let text = Text(AxisTicks.label(y, step: yStep)).font(labelFont).foregroundStyle(labelColor)
                context.draw(text, at: CGPoint(x: yLabelX, y: screenY), anchor: yLabelAnchor)
            }

            if xAxisVisible, yAxisVisible {
                let text = Text("0").font(labelFont).foregroundStyle(labelColor)
                context.draw(text, at: CGPoint(x: originX - 6, y: originY + 5), anchor: .topTrailing)
            }
        }

        // MARK: Area

        /// Shades the signed area between f and the x-axis over `bounds`: blue
        /// above the axis, red below.
        static func drawArea(in context: inout GraphicsContext, _ geometry: CalculusPlotGeometry, f: CompiledExpr, bounds: ClosedRange<Double>) {
            let visible = geometry.xRange
            let lower = max(bounds.lowerBound, visible.lowerBound)
            let upper = min(bounds.upperBound, visible.upperBound)
            guard upper > lower else { return }

            let polylines = geometry.polylines({ f($0) }, over: lower...upper)
            let baseline = geometry.screenY(0)
            var above = Path()
            var below = Path()
            // How far each region reaches from the axis, so its gradient spans it.
            var highest = baseline
            var lowest = baseline
            for line in polylines {
                guard let first = line.first, let last = line.last else { continue }
                let start = CGPoint(x: geometry.screenX(first.x), y: baseline)
                let end = CGPoint(x: geometry.screenX(last.x), y: baseline)
                above.move(to: start)
                below.move(to: start)
                for plotPoint in line {
                    let abovePoint = geometry.point(plotPoint.x, max(plotPoint.y, 0))
                    let belowPoint = geometry.point(plotPoint.x, min(plotPoint.y, 0))
                    above.addLine(to: abovePoint)
                    below.addLine(to: belowPoint)
                    highest = min(highest, abovePoint.y)
                    lowest = max(lowest, belowPoint.y)
                }
                above.addLine(to: end)
                below.addLine(to: end)
                above.closeSubpath()
                below.closeSubpath()
            }

            // Strongest at the curve, fading toward the axis. Clamping to the
            // view keeps the fade visible when the curve runs off screen.
            let axis = CGPoint(x: 0, y: baseline)
            let top = CGPoint(x: 0, y: min(baseline - 1, max(highest, 0)))
            let bottom = CGPoint(x: 0, y: max(baseline + 1, min(lowest, geometry.size.height)))
            let positive = Gradient(colors: [CalculusPalette.positiveArea.opacity(0.46), CalculusPalette.positiveArea.opacity(0.14)])
            let negative = Gradient(colors: [CalculusPalette.negativeArea.opacity(0.14), CalculusPalette.negativeArea.opacity(0.46)])
            context.fill(above, with: .linearGradient(positive, startPoint: top, endPoint: axis))
            context.fill(below, with: .linearGradient(negative, startPoint: axis, endPoint: bottom))
        }

        // MARK: Markers

        /// Roots as rings, maxima and minima as triangles pointing the way the
        /// curve bends, inflection points as diamonds. Where features crowd
        /// closer together than the screen can resolve, as `sin(1/x)`'s do near
        /// 0, their markers are left out rather than piled up.
        static func drawFeatures(in context: inout GraphicsContext, _ geometry: CalculusPlotGeometry, _ features: CurveFeatures) {
            let outline = Color.black.opacity(0.6)

            let inflections = features.inflectionPoints.map { geometry.point($0.x, $0.y) }
            for index in resolved(inflections, geometry) {
                let shape = diamond(at: inflections[index], radius: 5.5)
                context.fill(shape, with: .color(CalculusPalette.inflection))
                context.stroke(shape, with: .color(outline), lineWidth: 1)
            }

            let extrema = features.extrema.map { geometry.point($0.x, $0.y) }
            for index in resolved(extrema, geometry) {
                let isMaximum = features.extrema[index].kind == .maximum
                let shape = triangle(at: extrema[index], pointingUp: isMaximum, radius: 7)
                context.fill(shape, with: .color(CalculusPalette.extremum))
                context.stroke(shape, with: .color(outline), lineWidth: 1)
            }

            let roots = features.roots.map { geometry.point($0, 0) }
            for index in resolved(roots, geometry) {
                let center = roots[index]
                let ring = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
                context.fill(ring, with: .color(Color(white: 0.07)))
                context.stroke(ring, with: .color(CalculusPalette.root), lineWidth: 2)
            }
        }

        /// Indices of the visible points (sorted by x) that are at least a
        /// marker's width from both neighbors.
        private static func resolved(_ points: [CGPoint], _ geometry: CalculusPlotGeometry) -> [Int] {
            let gap: CGFloat = 10
            return points.indices.filter { index in
                guard geometry.isVisible(points[index]) else { return false }
                let clearOfPrevious = index == 0 || points[index].x - points[index - 1].x >= gap
                let clearOfNext = index == points.count - 1 || points[index + 1].x - points[index].x >= gap
                return clearOfPrevious && clearOfNext
            }
        }

        static func triangle(at center: CGPoint, pointingUp: Bool, radius: CGFloat) -> Path {
            let direction: CGFloat = pointingUp ? -1 : 1
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y + direction * radius))
            path.addLine(to: CGPoint(x: center.x + radius * 0.9, y: center.y - direction * radius * 0.55))
            path.addLine(to: CGPoint(x: center.x - radius * 0.9, y: center.y - direction * radius * 0.55))
            path.closeSubpath()
            return path
        }

        static func diamond(at center: CGPoint, radius: CGFloat) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - radius))
            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.closeSubpath()
            return path
        }
    }
}
