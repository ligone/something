import CalculusKit
import SwiftUI

/// Everything that follows the pointer: the crosshair, the tangent line and
/// its read-out, and the draggable handles. Kept apart from ``CalculusPlotCanvas``
/// so that moving the pointer redraws only this light layer.
struct CalculusPlotOverlay: View {
    let model: CalculusModel

    var body: some View {
        let viewport = model.viewport
        let size = model.plotSize
        let dragged = model.draggedHandle
        let isInteracting = model.isPanning || dragged != nil
        let hover = isInteracting ? nil : model.hoverLocation
        let hoveredHandle = hover.flatMap { model.handle(at: $0) }
        let probe = hoveredHandle == nil ? hover.flatMap { model.probe(at: $0) } : nil
        let marks = model.visibleHandles.map { handle in
            HandleMark(
                handle: handle,
                value: model.value(of: handle),
                knob: model.knobCenter(for: handle),
                isActive: handle == dragged || handle == hoveredHandle
            )
        }
        let taylorCenter = model.taylorCenter
        let taylorValue = model.analysis.f(taylorCenter)
        let taylorOrder = model.taylorOrder

        ZStack(alignment: .topLeading) {
            Canvas { context, canvasSize in
                let geometry = CalculusPlotGeometry(viewport: viewport, size: canvasSize)
                let anchor: CGPoint? = taylorValue.isFinite ? geometry.point(taylorCenter, taylorValue) : nil
                OverlayPainter.drawHandles(marks, taylorAnchor: anchor, dragged: dragged, in: &context, geometry)
                if let probe {
                    OverlayPainter.drawProbe(probe, in: &context, geometry)
                }
            }

            if let probe, size.width > 0 {
                HoverCard(probe: probe, taylorOrder: taylorOrder)
                    .position(cardCenter(for: probe, viewport: viewport, size: size))
            }
        }
    }

    /// Beside the probed point, flipped to stay inside the plot.
    private func cardCenter(for probe: HoverProbe, viewport: CalculusViewport, size: CGSize) -> CGPoint {
        let width = HoverCard.width
        var lines: CGFloat = 4
        if probe.feature != nil { lines += 1 }
        if probe.taylorValue != nil { lines += 1 }
        let height = lines * 17 + 22
        let anchorX = viewport.screenX(probe.x, in: size)
        let rawY = probe.y.isFinite ? viewport.screenY(probe.y, in: size) : size.height / 2
        let anchorY = min(max(rawY, 0), size.height)

        var x = anchorX + 24 + width / 2
        if x + width / 2 > size.width - 10 {
            x = anchorX - 24 - width / 2
        }
        var y = anchorY + 24 + height / 2
        if y + height / 2 > size.height - 10 {
            y = anchorY - 24 - height / 2
        }
        x = min(max(x, width / 2 + 10), max(width / 2 + 10, size.width - width / 2 - 10))
        y = min(max(y, height / 2 + 10), max(height / 2 + 10, size.height - height / 2 - 10))
        return CGPoint(x: x, y: y)
    }
}

extension CalculusPlotOverlay {
    /// The point under the pointer: where it meets the curve, the slope there,
    /// and the feature it snapped to, if any.
    fileprivate struct HoverProbe {
        enum Feature {
            case root, maximum, minimum, inflection

            var title: String {
                switch self {
                case .root: "Root"
                case .maximum: "Local maximum"
                case .minimum: "Local minimum"
                case .inflection: "Inflection point"
                }
            }

            var color: Color {
                switch self {
                case .root: CalculusPalette.root
                case .maximum, .minimum: CalculusPalette.extremum
                case .inflection: CalculusPalette.inflection
                }
            }
        }

        var x: Double
        var y: Double
        var slope: Double
        var taylorValue: Double?
        var feature: Feature?

        /// The tangent line as an equation, `y = 1.37x − 0.52`.
        var tangentEquation: String? {
            guard y.isFinite, slope.isFinite else { return nil }
            let intercept = y - slope * x
            if abs(slope) < 1e-12 {
                return "y = " + MathPrinter.decimal(y, significantDigits: 4)
            }
            let magnitude = MathPrinter.decimal(abs(slope), significantDigits: 4)
            var text = "y = " + (slope < 0 ? "−" : "") + (magnitude == "1" ? "" : magnitude) + "x"
            if abs(intercept) > 1e-12 * max(1, abs(y)) {
                text += (intercept < 0 ? " − " : " + ") + MathPrinter.decimal(abs(intercept), significantDigits: 4)
            }
            return text
        }
    }

    /// A handle as drawn: where its knob is and whether it's lit.
    fileprivate struct HandleMark {
        let handle: CalculusHandle
        let value: Double
        let knob: CGPoint
        let isActive: Bool

        var label: String {
            switch handle {
            case .lowerBound: "a"
            case .upperBound: "b"
            case .taylorCenter: "x₀"
            }
        }

        var color: Color {
            handle == .taylorCenter ? CalculusPalette.taylor : CalculusPalette.positiveArea
        }
    }

    /// The read-out that follows the pointer.
    fileprivate struct HoverCard: View {
        static let width: CGFloat = 196

        let probe: HoverProbe
        let taylorOrder: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                if let feature = probe.feature {
                    Text(feature.title.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(feature.color)
                        .padding(.bottom, 1)
                }
                row("x", probe.x, color: Color.white.opacity(0.45))
                row("f(x)", probe.y, color: CalculusPalette.function)
                row("f′(x)", probe.slope, color: CalculusPalette.derivative)
                if let taylorValue = probe.taylorValue {
                    row("T\(MathPrinter.subscriptDigits(taylorOrder))(x)", taylorValue, color: CalculusPalette.taylor)
                }
                if let equation = probe.tangentEquation {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.5)
                        .padding(.vertical, 3)
                    Text(equation)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(width: Self.width, alignment: .leading)
            .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        }

        private func row(_ label: String, _ value: Double, color: Color) -> some View {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer(minLength: 6)
                Text(value.isFinite ? MathPrinter.decimal(value, significantDigits: 6) : "undefined")
                    .foregroundStyle(Color.white)
            }
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
        }
    }

    /// Drawing for the overlay layer.
    fileprivate enum OverlayPainter {
        static func drawHandles(
            _ marks: [HandleMark],
            taylorAnchor: CGPoint?,
            dragged: CalculusHandle?,
            in context: inout GraphicsContext,
            _ geometry: CalculusPlotGeometry
        ) {
            let height = geometry.size.height
            for mark in marks {
                let x = CalculusPlotGeometry.crisp(mark.knob.x)
                guard x > -30, x < geometry.size.width + 30 else { continue }

                var guide = Path()
                switch mark.handle {
                case .lowerBound, .upperBound:
                    guide.move(to: CGPoint(x: x, y: 0))
                    guide.addLine(to: CGPoint(x: x, y: height))
                    let opacity = mark.isActive ? 0.9 : 0.42
                    context.stroke(guide, with: .color(mark.color.opacity(opacity)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                case .taylorCenter:
                    if let anchor = taylorAnchor {
                        guide.move(to: CGPoint(x: x, y: mark.knob.y))
                        guide.addLine(to: CGPoint(x: x, y: anchor.y))
                        let opacity = mark.isActive ? 0.95 : 0.6
                        context.stroke(guide, with: .color(mark.color.opacity(opacity)), style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                        // Hollow, so a marker at the same spot still shows through.
                        let ring = Path(ellipseIn: CGRect(x: anchor.x - 8, y: anchor.y - 8, width: 16, height: 16))
                        context.stroke(ring, with: .color(Color.black.opacity(0.5)), lineWidth: 4)
                        context.stroke(ring, with: .color(mark.color), lineWidth: 2)
                    }
                }
                drawKnob(mark, in: &context)
                if mark.handle == dragged {
                    drawValueTag(for: mark, in: &context)
                }
            }
        }

        private static func drawKnob(_ mark: HandleMark, in context: inout GraphicsContext) {
            let scale: CGFloat = mark.isActive ? 1.15 : 1
            let width: CGFloat = (mark.handle == .taylorCenter ? 28 : 22) * scale
            let height: CGFloat = 18 * scale
            let rect = CGRect(x: mark.knob.x - width / 2, y: mark.knob.y - height / 2, width: width, height: height)
            let shape = Path(roundedRect: rect, cornerRadius: height / 2)
            context.fill(shape, with: .color(mark.color))
            let border = mark.isActive ? Color.white : Color.black.opacity(0.35)
            context.stroke(shape, with: .color(border), lineWidth: mark.isActive ? 1.5 : 1)
            let label = Text(mark.label)
                .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.78))
            context.draw(label, at: mark.knob, anchor: .center)
        }

        /// `a = 0.5236` beside a knob being dragged.
        private static func drawValueTag(for mark: HandleMark, in context: inout GraphicsContext) {
            let text = Text("\(mark.label) = \(MathPrinter.decimal(mark.value, significantDigits: 5))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white)
            let resolved = context.resolve(text)
            let textSize = resolved.measure(in: CGSize(width: 300, height: 40))
            let offset: CGFloat = mark.handle == .taylorCenter ? -26 : 26
            let center = CGPoint(x: mark.knob.x, y: mark.knob.y + offset)
            let background = CGRect(
                x: center.x - textSize.width / 2 - 8,
                y: center.y - textSize.height / 2 - 4,
                width: textSize.width + 16,
                height: textSize.height + 8
            )
            let pill = Path(roundedRect: background, cornerRadius: background.height / 2)
            context.fill(pill, with: .color(Color.black.opacity(0.75)))
            context.stroke(pill, with: .color(mark.color.opacity(0.7)), lineWidth: 1)
            context.draw(resolved, at: center, anchor: .center)
        }

        /// The crosshair, the tangent line fading out in both directions, and a
        /// glowing dot on the curve.
        static func drawProbe(_ probe: HoverProbe, in context: inout GraphicsContext, _ geometry: CalculusPlotGeometry) {
            let size = geometry.size
            let x = CalculusPlotGeometry.crisp(geometry.screenX(probe.x))
            var guide = Path()
            guide.move(to: CGPoint(x: x, y: 0))
            guide.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(guide, with: .color(Color.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

            guard probe.y.isFinite else { return }
            let point = geometry.point(probe.x, probe.y)

            if probe.slope.isFinite {
                // The slope in screen space, where y points down.
                let viewport = geometry.viewport
                let screenSlope = -probe.slope * viewport.unitsPerPointX / viewport.unitsPerPointY
                let norm = (1 + screenSlope * screenSlope).squareRoot()
                let reach: CGFloat = 240
                let dx = CGFloat(1 / norm) * reach
                let dy = CGFloat(screenSlope / norm) * reach
                let start = CGPoint(x: point.x - dx, y: point.y - dy)
                let end = CGPoint(x: point.x + dx, y: point.y + dy)
                var tangent = Path()
                tangent.move(to: start)
                tangent.addLine(to: end)
                let fade = Gradient(stops: [
                    Gradient.Stop(color: Color.white.opacity(0), location: 0),
                    Gradient.Stop(color: Color.white.opacity(0.9), location: 0.5),
                    Gradient.Stop(color: Color.white.opacity(0), location: 1),
                ])
                context.stroke(
                    tangent,
                    with: .linearGradient(fade, startPoint: start, endPoint: end),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }

            let glowRect = CGRect(x: point.x - 15, y: point.y - 15, width: 30, height: 30)
            let glow = Gradient(colors: [CalculusPalette.function.opacity(0.55), CalculusPalette.function.opacity(0)])
            context.fill(Path(ellipseIn: glowRect), with: .radialGradient(glow, center: point, startRadius: 0, endRadius: 15))
            let dot = Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
            context.fill(dot, with: .color(Color.white))
            context.stroke(dot, with: .color(CalculusPalette.function), lineWidth: 2)
        }
    }
}

extension CalculusModel {
    /// What the pointer at `location` is probing. Within a few points of a
    /// root, extremum or inflection point, it snaps to it.
    fileprivate func probe(at location: CGPoint) -> CalculusPlotOverlay.HoverProbe? {
        guard plotSize.width > 0 else { return nil }
        var x = viewport.plotX(location.x, in: plotSize)
        var feature: CalculusPlotOverlay.HoverProbe.Feature?
        if showsFeatures, let snapped = nearestFeature(toScreenX: location.x) {
            x = snapped.x
            feature = snapped.feature
        }
        let y = analysis.f(x)
        let slope = y.isFinite ? analysis.fPrime(x) : .nan
        var taylorValue: Double?
        if showsTaylor, taylorSeries.isDefined(through: taylorOrder) {
            taylorValue = taylorSeries.evaluate(at: x, order: taylorOrder)
        }
        return CalculusPlotOverlay.HoverProbe(x: x, y: y, slope: slope, taylorValue: taylorValue, feature: feature)
    }

    private func nearestFeature(toScreenX screenX: CGFloat) -> (x: Double, feature: CalculusPlotOverlay.HoverProbe.Feature)? {
        var best: (x: Double, feature: CalculusPlotOverlay.HoverProbe.Feature)?
        var bestDistance: CGFloat = 7
        func consider(_ x: Double, _ feature: CalculusPlotOverlay.HoverProbe.Feature) {
            let distance = abs(viewport.screenX(x, in: plotSize) - screenX)
            if distance < bestDistance {
                bestDistance = distance
                best = (x, feature)
            }
        }
        for point in features.inflectionPoints { consider(point.x, .inflection) }
        for root in features.roots { consider(root, .root) }
        for extremum in features.extrema { consider(extremum.x, extremum.kind == .maximum ? .maximum : .minimum) }
        return best
    }
}
