import FractalKit
import SwiftUI

struct FractalExhibit: View {
    @State private var model = FractalModel()

    var body: some View {
        ExhibitLayout(.fractals) {
            switch FractalGPU.shared {
            case .success(let gpu):
                FractalStage(gpu: gpu, model: model)
            case .failure(let error):
                ContentUnavailableView(
                    "Metal Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            }
        } controls: {
            FractalControls(model: model)
        }
    }
}

// MARK: - Stage

private struct FractalStage: View {
    let gpu: FractalGPU
    let model: FractalModel

    var body: some View {
        FractalCanvas(gpu: gpu, model: model)
            .overlay(alignment: .topLeading) { FractalHUD(model: model) }
            .overlay { JuliaInsetFrame(model: model) }
            .overlay(alignment: .bottomLeading) { TourCaption(model: model) }
            .stageHint(model.kind.isJulia
                ? "Drag to pan · Scroll or pinch to zoom · ⌥-drag to morph the set · J returns"
                : "Drag to pan · Scroll or pinch to zoom · Double-click to dive · Hover for Julia sets")
    }
}

private struct FractalHUD: View {
    let model: FractalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatPill("Zoom", FractalFormat.magnification(model.magnification))
                StatPill("Iterations", model.renderedIterations.formatted())
                StatPill("Math", model.renderedPrecisely ? "double-float" : "float32")
                StatPill("GPU", String(format: "%.1f ms", model.gpuMilliseconds))
            }
            StatPill("Center", FractalFormat.complex(re: model.viewport.centerX, im: model.viewport.centerY, scale: model.viewport.scale))
        }
        .padding(14)
        .allowsHitTesting(false)
    }
}

/// Frames the Julia preview that the renderer draws into the corner.
private struct JuliaInsetFrame: View {
    let model: FractalModel

    var body: some View {
        if let c = model.juliaPreviewParameter {
            let rect = model.juliaInsetRect
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                Text("Julia set for c = \(FractalFormat.complex(re: c.re, im: c.im, scale: 1e-4))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .offset(y: 26)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

/// The caption card shown at each stop of the guided tour.
private struct TourCaption: View {
    let model: FractalModel

    var body: some View {
        Group {
            if let landmark = model.arrivedLandmark {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Exhibit.fractals.tint)
                        Text(landmark.name)
                            .font(.headline)
                        Spacer(minLength: 12)
                        if model.isTouring {
                            Text("\(model.tourIndex + 1) of \(FractalLandmark.tour.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(landmark.caption)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(FractalFormat.magnification(model.magnification) + " magnification")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(16)
                .frame(maxWidth: 380, alignment: .leading)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .padding(.leading, 16)
                .padding(.bottom, 56)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .id(landmark.name)
            } else if let destination = model.destination {
                Label("Flying to \(destination.name)…", systemImage: "airplane")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.leading, 16)
                    .padding(.bottom, 56)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: model.arrivedLandmark?.name)
        .animation(.easeInOut(duration: 0.3), value: model.destination?.name)
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

private struct FractalControls: View {
    @Bindable var model: FractalModel

    private var isJulia: Binding<Bool> {
        Binding(
            get: { model.kind.isJulia },
            set: { wantsJulia in
                if wantsJulia { model.toggleJulia() } else { model.showMandelbrot() }
            }
        )
    }

    var body: some View {
        ControlSection("Fractal") {
            Picker("Fractal", selection: isJulia) {
                Text("Mandelbrot").tag(false)
                Text("Julia").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if case let .julia(re, im) = model.kind {
                StatRow("c", FractalFormat.complex(re: re, im: im, scale: 1e-5))
                Text("⌥-drag on the stage to morph the set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Julia preview on hover", isOn: $model.showsJuliaPreview)
                Text("Every point of the Mandelbrot set is the parameter of a Julia set. Click the preview to explore it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        ControlSection("Guided Tour") {
            Button {
                model.isTouring ? model.stopTour() : model.startTour()
            } label: {
                Label(model.isTouring ? "Stop the Tour" : "Take the Tour", systemImage: model.isTouring ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Exhibit.fractals.tint)
            .controlSize(.large)

            VStack(spacing: 2) {
                ForEach(Array(FractalLandmark.tour.enumerated()), id: \.element.id) { index, landmark in
                    LandmarkRow(
                        landmark: landmark,
                        isCurrent: model.isTouring && model.tourIndex == index
                    ) {
                        model.fly(to: landmark)
                    }
                }
            }
        }

        ControlSection("Color") {
            PaletteGrid(selection: $model.palette)
            ParameterSlider("Color density", value: $model.colorDensity, in: 0.03...0.4) {
                String(format: "%.2f", $0)
            }
            Toggle("Cycle colors", isOn: $model.cyclesColors)
        }

        ControlSection("Rendering") {
            ParameterSlider("Detail", value: $model.detail, in: 0.5...4) {
                String(format: "%.1f×", $0)
            }
            Toggle("Supersample when still", isOn: $model.antialiasing)
            StatRow("Resolution", "\(Int(model.renderedPixels.width)) × \(Int(model.renderedPixels.height))")
            HStack {
                Button("Reset View") { model.resetView() }
                Spacer()
                Text("R · J · T · arrows · ±")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct LandmarkRow: View {
    let landmark: FractalLandmark
    let isCurrent: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isCurrent ? "location.fill" : "location")
                    .foregroundStyle(isCurrent ? Exhibit.fractals.tint : .secondary)
                    .frame(width: 16)
                Text(landmark.name)
                    .lineLimit(1)
                Spacer()
                Text(FractalFormat.magnification(3.1 / landmark.width))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Fly to \(landmark.name)")
    }
}

/// Clickable gradient swatches, one per palette.
private struct PaletteGrid: View {
    @Binding var selection: FractalPalette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
            ForEach(FractalPalette.all) { palette in
                Button {
                    selection = palette
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: Self.swatch(palette), startPoint: .leading, endPoint: .trailing))
                            .frame(height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        selection.name == palette.name ? Color.accentColor : Color.primary.opacity(0.15),
                                        lineWidth: selection.name == palette.name ? 2 : 0.5
                                    )
                            )
                        Text(palette.name)
                            .font(.caption)
                            .foregroundStyle(selection.name == palette.name ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func swatch(_ palette: FractalPalette) -> [Color] {
        stride(from: 0.0, to: 1.0, by: 1.0 / 12).map { t in
            let c = palette.color(at: t)
            return Color(red: c.red, green: c.green, blue: c.blue)
        }
    }
}

// MARK: - Formatting

enum FractalFormat {
    /// "250×", "3.2 × 10⁹"
    static func magnification(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        if value < 10_000 {
            return value < 10 ? String(format: "%.1f×", value) : String(format: "%.0f×", value)
        }
        let exponent = Int(floor(log10(value)))
        let mantissa = value / pow(10, Double(exponent))
        return String(format: "%.1f × 10", mantissa) + superscript(exponent)
    }

    /// Enough digits to resolve the current scale, and no more.
    static func complex(re: Double, im: Double, scale: Double) -> String {
        let digits = min(16, max(3, Int(ceil(-log10(max(scale, 1e-17)))) + 1))
        let sign = im < 0 ? "−" : "+"
        let real = String(format: "%.\(digits)f", re).replacingOccurrences(of: "-", with: "−")
        let imaginary = String(format: "%.\(digits)f", abs(im))
        return "\(real) \(sign) \(imaginary)i"
    }

    private static func superscript(_ n: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        let body = String(abs(n)).map { digits[Int(String($0))!] }
        return (n < 0 ? "⁻" : "") + String(body)
    }
}
