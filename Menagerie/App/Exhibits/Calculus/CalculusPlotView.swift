import CalculusKit
import SwiftUI

/// The interactive plot: the two canvas layers, the gestures that drive
/// them, a legend and feature counts.
struct CalculusPlotView: View {
    let model: CalculusModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CalculusPlotCanvas(model: model)
                CalculusPlotOverlay(model: model)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    model.hoverLocation = location
                case .ended:
                    model.hoverLocation = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        model.dragChanged(start: value.startLocation, location: value.location, translation: value.translation)
                    }
                    .onEnded { _ in
                        model.dragEnded()
                    }
            )
            .onTapGesture(count: 2) {
                model.resetView()
            }
            .onScrollWheel { event in
                model.zoom(by: Double(event.zoomFactor), around: event.location, modifiers: event.modifiers)
            }
            .onAppear {
                model.setPlotSize(proxy.size)
            }
            .onChange(of: proxy.size) { _, size in
                model.setPlotSize(size)
            }
        }
        .overlay(alignment: .topTrailing) {
            PlotLegend(model: model)
                .padding(14)
                .allowsHitTesting(false)
        }
        .stageHUD(.topLeading) {
            FeatureCounts(model: model)
        }
        .stageHint("Hover for tangents · Drag to pan · Scroll to zoom · Double-click to reset")
    }
}

extension CalculusPlotView {
    /// How many roots, extrema and inflection points are in view.
    fileprivate struct FeatureCounts: View {
        let model: CalculusModel

        var body: some View {
            if model.showsFeatures {
                let features = model.visibleFeatures
                StatPill("Roots", "\(features.roots.count)")
                StatPill("Extrema", "\(features.extrema.count)")
                StatPill("Inflections", "\(features.inflectionPoints.count)")
            }
        }
    }

    /// Which curve is which.
    fileprivate struct PlotLegend: View {
        let model: CalculusModel

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                LegendRow(label: "f(x)", color: CalculusPalette.function, style: .solid)
                if model.showsDerivative {
                    LegendRow(label: "f′(x)", color: CalculusPalette.derivative, style: .solid)
                }
                if model.showsSecondDerivative {
                    LegendRow(label: "f″(x)", color: CalculusPalette.secondDerivative, style: .solid)
                }
                if model.showsTaylor {
                    LegendRow(label: taylorLabel, color: CalculusPalette.taylor, style: .dashed)
                }
                if model.showsIntegral {
                    LegendRow(label: integralLabel, color: CalculusPalette.positiveArea, style: .area)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .fixedSize()
        }

        private var taylorLabel: String {
            let order = MathPrinter.subscriptDigits(model.taylorOrder)
            let center = MathPrinter.decimal(model.taylorCenter, significantDigits: 3)
            return "T\(order)(x) at x₀ = \(center)"
        }

        private var integralLabel: String {
            guard let integral = model.integral else { return "∫ f(x) dx" }
            switch integral.status {
            case .converged, .approximate:
                let prefix = integral.status == .approximate ? "≈ " : "= "
                return "∫ f(x) dx " + prefix + MathPrinter.decimal(integral.value, significantDigits: 6)
            case .divergent:
                return "∫ f(x) dx diverges"
            case .undefined:
                return "∫ f(x) dx undefined"
            }
        }
    }

    fileprivate struct LegendRow: View {
        enum Style {
            case solid, dashed, area
        }

        let label: String
        let color: Color
        let style: Style

        var body: some View {
            HStack(spacing: 8) {
                swatch
                    .frame(width: 22, height: 10)
                Text(label)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
        }

        @ViewBuilder
        private var swatch: some View {
            switch style {
            case .area:
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(color.opacity(0.85), lineWidth: 1)
                    )
            case .solid, .dashed:
                let dash: [CGFloat] = style == .dashed ? [4, 3.5] : []
                Canvas { context, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 1.5, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width - 1.5, y: size.height / 2))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: dash))
                }
            }
        }
    }
}
