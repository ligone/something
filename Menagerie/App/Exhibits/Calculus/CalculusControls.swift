import CalculusKit
import SwiftUI

/// The control panel: the function and its derivatives, the layer switches,
/// the Taylor and integral settings, the features in view, and the view.
struct CalculusControls: View {
    let model: CalculusModel

    var body: some View {
        VStack(alignment: .leading, spacing: ExhibitMetrics.sectionSpacing) {
            ControlSection("Function") {
                FunctionSummary(model: model)
            }
            ControlSection("Layers") {
                LayerToggles(model: model)
            }
            ControlSection("Taylor Polynomial") {
                TaylorControls(model: model)
            }
            ControlSection("Integral") {
                IntegralControls(model: model)
            }
            ControlSection("In View") {
                FeatureSummary(model: model)
            }
            ControlSection("View") {
                ViewControls(model: model)
            }
        }
    }
}

extension CalculusControls {
    /// f, f′ and f″, pretty-printed and selectable.
    fileprivate struct FunctionSummary: View {
        let model: CalculusModel

        var body: some View {
            VStack(alignment: .leading, spacing: 11) {
                ExpressionRow(title: "f(x)", color: CalculusPalette.function, expression: model.analysis.function)
                ExpressionRow(title: "f′(x)", color: CalculusPalette.derivative, expression: model.analysis.firstDerivative)
                ExpressionRow(title: "f″(x)", color: CalculusPalette.secondDerivative, expression: model.analysis.secondDerivative)
            }
        }
    }

    fileprivate struct ExpressionRow: View {
        let title: String
        let color: Color
        let expression: MathExpr

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(expression.description)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Switches for each layer of the plot.
    fileprivate struct LayerToggles: View {
        @Bindable var model: CalculusModel

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                LayerToggle(title: "Derivative f′", color: CalculusPalette.derivative, isOn: $model.showsDerivative)
                LayerToggle(title: "Second derivative f″", color: CalculusPalette.secondDerivative, isOn: $model.showsSecondDerivative)
                LayerToggle(title: "Taylor polynomial", color: CalculusPalette.taylor, isOn: $model.showsTaylor)
                LayerToggle(title: "Area under f", color: CalculusPalette.positiveArea, isOn: $model.showsIntegral)
                LayerToggle(title: "Roots, extrema, inflections", color: CalculusPalette.extremum, isOn: $model.showsFeatures)
            }
        }
    }

    fileprivate struct LayerToggle: View {
        let title: String
        let color: Color
        @Binding var isOn: Bool

        var body: some View {
            Toggle(isOn: $isOn) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color)
                        .frame(width: 12, height: 3)
                    Text(title)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)
        }
    }

    /// The Taylor polynomial's order and center, and the polynomial itself.
    fileprivate struct TaylorControls: View {
        @Bindable var model: CalculusModel

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ParameterSlider("Order n", value: orderBinding, in: 0...Double(CalculusModel.maximumTaylorOrder), step: 1) {
                    "\(Int($0))"
                }
                ParameterSlider("Center x₀", value: $model.taylorCenter, in: -10...10) {
                    MathPrinter.decimal($0, significantDigits: 3)
                }

                polynomial

                HStack {
                    Button {
                        model.toggleTaylorSweep()
                    } label: {
                        Label(
                            model.isSweepingTaylorOrder ? "Stop" : "Sweep n from 0 to 12",
                            systemImage: model.isSweepingTaylorOrder ? "stop.fill" : "play.fill"
                        )
                    }
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }
                Text("Drag the x₀ handle on the plot to move the center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private var orderBinding: Binding<Double> {
            Binding(
                get: { Double(model.taylorOrder) },
                set: { model.setTaylorOrder(Int($0.rounded())) }
            )
        }

        @ViewBuilder
        private var polynomial: some View {
            let series = model.taylorSeries
            let order = model.taylorOrder
            let name = "T\(MathPrinter.subscriptDigits(order))(x)"
            if series.isDefined(through: order) {
                Text("\(name) = \(series.polynomialDescription(order: order, significantDigits: 4))")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("f has no Taylor polynomial of order \(order) at x₀ = \(MathPrinter.decimal(model.taylorCenter, significantDigits: 3)): a derivative doesn't exist there.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The integral's bounds and value.
    fileprivate struct IntegralControls: View {
        @Bindable var model: CalculusModel

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ParameterSlider("Lower bound a", value: $model.lowerBound, in: -10...10) {
                    IntegralReadout.bound($0)
                }
                ParameterSlider("Upper bound b", value: $model.upperBound, in: -10...10) {
                    IntegralReadout.bound($0)
                }
                IntegralReadout(
                    result: model.integral,
                    lower: model.lowerBound,
                    upper: model.upperBound,
                    isUpdating: model.integralIsUpdating
                )
            }
        }
    }

    fileprivate struct IntegralReadout: View {
        let result: IntegralResult?
        let lower: Double
        let upper: Double
        let isUpdating: Bool

        /// A bound, written as π or e when it is one.
        static func bound(_ value: Double) -> String {
            if let form = ClosedForm.recognize(value, tolerance: 1e-12), form.count <= 4, form.contains("π") || form == "e" {
                return form
            }
            return MathPrinter.decimal(value, significantDigits: 4)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 5) {
                    Text("∫")
                        .font(.system(size: 30, weight: .light, design: .serif))
                    VStack(alignment: .leading, spacing: 9) {
                        Text(Self.bound(upper))
                        Text(Self.bound(lower))
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    Text("f(x) dx")
                        .font(.system(.body, design: .serif).italic())
                    Spacer(minLength: 8)
                    Text(valueText)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .opacity(isUpdating ? 0.65 : 1)
            .animation(.easeOut(duration: 0.15), value: isUpdating)
        }

        private var valueText: String {
            guard let result else { return "…" }
            switch result.status {
            case .converged: return MathPrinter.decimal(result.value, significantDigits: 9)
            case .approximate: return "≈ " + MathPrinter.decimal(result.value, significantDigits: 4)
            case .divergent: return "diverges"
            case .undefined: return "undefined"
            }
        }

        private var valueColor: Color {
            guard let result else { return .secondary }
            switch result.status {
            case .converged, .approximate: return .primary
            case .divergent, .undefined: return CalculusPalette.error
            }
        }

        private var detail: String {
            guard let result else { return "Integrating…" }
            switch result.status {
            case .converged:
                if let form = ClosedForm.recognize(result.value), form != MathPrinter.decimal(result.value, significantDigits: 9) {
                    return "That's \(form), to within rounding. Adaptive Simpson used \(result.evaluations) samples."
                }
                return "Adaptive Simpson used \(result.evaluations) samples."
            case .approximate:
                return "A best estimate: f oscillates too wildly to pin down."
            case .divergent:
                return "f has a singularity between a and b that the area can't survive."
            case .undefined:
                return "f isn't defined everywhere between a and b."
            }
        }
    }

    /// Lists of the landmarks currently in view.
    fileprivate struct FeatureSummary: View {
        let model: CalculusModel

        var body: some View {
            let features = model.visibleFeatures
            let maxima = features.extrema.filter { $0.kind == .maximum }
            let minima = features.extrema.filter { $0.kind == .minimum }
            VStack(alignment: .leading, spacing: 10) {
                FeatureLine(title: "Roots", symbol: "circle", color: CalculusPalette.root, entries: features.roots.map { Self.format($0) })
                FeatureLine(title: "Maxima", symbol: "triangle.fill", color: CalculusPalette.extremum, entries: maxima.map { Self.format($0.x, $0.y) })
                FeatureLine(title: "Minima", symbol: "triangle.fill", flipped: true, color: CalculusPalette.extremum, entries: minima.map { Self.format($0.x, $0.y) })
                FeatureLine(title: "Inflection points", symbol: "diamond.fill", color: CalculusPalette.inflection, entries: features.inflectionPoints.map { Self.format($0.x, $0.y) })
            }
        }

        static func format(_ value: Double) -> String {
            abs(value) < 1e-10 ? "0" : MathPrinter.decimal(value, significantDigits: 5)
        }

        static func format(_ x: Double, _ y: Double) -> String {
            "(\(format(x)), \(format(y)))"
        }
    }

    fileprivate struct FeatureLine: View {
        let title: String
        let symbol: String
        var flipped = false
        let color: Color
        let entries: [String]

        private static let shown = 6

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(flipped ? 180 : 0))
                        .foregroundStyle(color)
                        .shadow(color: .black.opacity(0.35), radius: 0.5)
                        .frame(width: 10)
                    Text(title)
                        .font(.callout)
                    Spacer(minLength: 6)
                    Text("\(entries.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !entries.isEmpty {
                    Text(listText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 16)
                }
            }
        }

        private var listText: String {
            var text = entries.prefix(Self.shown).joined(separator: "  ")
            if entries.count > Self.shown {
                text += "  … \(entries.count - Self.shown) more"
            }
            return text
        }
    }

    /// Resetting and zooming, and the visible ranges.
    fileprivate struct ViewControls: View {
        let model: CalculusModel

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        model.resetView()
                    } label: {
                        Label("Reset View", systemImage: "arrow.counterclockwise")
                    }
                    .help("Frame the function again (or double-click the plot)")
                    Spacer(minLength: 0)
                    Button {
                        model.zoom(by: 1 / 1.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Zoom out")
                    Button {
                        model.zoom(by: 1.5)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Zoom in")
                }
                .controlSize(.small)

                if model.plotSize.width > 0 {
                    let xRange = model.viewport.xRange(in: model.plotSize)
                    let yRange = model.viewport.yRange(in: model.plotSize)
                    StatRow("x", "\(Self.format(xRange.lowerBound)) … \(Self.format(xRange.upperBound))")
                    StatRow("y", "\(Self.format(yRange.lowerBound)) … \(Self.format(yRange.upperBound))")
                }
                Text("⌥-scroll stretches y; ⌘-scroll stretches x.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private static func format(_ value: Double) -> String {
            MathPrinter.decimal(value, significantDigits: 3)
        }
    }
}
