import Foundation
import SwiftUI
import TracerKit

/// The control panel: scene, lens, light transport and render settings.
struct PathTracerControls: View {
    let model: PathTracerModel

    var body: some View {
        ControlSection("Scene") {
            Picker("Scene", selection: presetBinding) {
                ForEach(TracerScenePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(model.preset.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            StatRow("Primitives", model.world.primitiveCount.formatted())
            StatRow("BVH nodes", model.world.bvhNodeCount.formatted())
            StatRow("Lights", lightSummary)
        }

        ControlSection("Lens") {
            ParameterSlider("Aperture", value: apertureBinding, in: 0...model.apertureLimit, step: 0.005,
                            format: { value in value == 0 ? "Pinhole" : String(format: "%.3f", value) })
            // The focus slider moves in log space, so near and far distances get
            // equal travel.
            ParameterSlider("Focus distance", value: focusBinding, in: logFocusRange,
                            format: { value in String(format: "%.2f", exp(value)) })
            Button {
                model.resetCamera()
            } label: {
                Label("Reset Camera", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }

        ControlSection("Light Transport") {
            ParameterSlider("Max bounces", value: bouncesBinding, in: 1...32, step: 1,
                            format: { value in String(format: "%.0f", value) })
            ParameterSlider("Exposure", value: exposureBinding, in: -3...3, step: 0.05,
                            format: { value in String(format: "%+.2f EV", value) })
        }

        ControlSection("Render") {
            Picker("Quality", selection: qualityBinding) {
                ForEach(PathTracerQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            PathTracerProgress(model: model)
            PathTracerRenderButtons(model: model)
        }
    }

    // MARK: Bindings

    private var presetBinding: Binding<TracerScenePreset> {
        Binding(get: { model.preset }, set: { model.select($0) })
    }

    private var apertureBinding: Binding<Double> {
        Binding(get: { model.aperture }, set: { model.setAperture($0) })
    }

    private var focusBinding: Binding<Double> {
        Binding(get: { log(model.focusDistance) }, set: { model.setFocusDistance(exp($0)) })
    }

    private var logFocusRange: ClosedRange<Double> {
        log(model.focusRange.lowerBound)...log(model.focusRange.upperBound)
    }

    private var bouncesBinding: Binding<Double> {
        Binding(get: { model.maxBounces }, set: { model.setMaxBounces($0) })
    }

    private var exposureBinding: Binding<Double> {
        Binding(get: { model.exposure }, set: { model.setExposure($0) })
    }

    private var qualityBinding: Binding<PathTracerQuality> {
        Binding(get: { model.quality }, set: { model.setQuality($0) })
    }

    private var lightSummary: String {
        var parts: [String] = []
        let quads = model.world.lightCount
        if quads > 0 {
            parts.append(quads == 1 ? "1 area light" : "\(quads) area lights")
        }
        if model.world.scene.sky.sun != nil {
            parts.append("sun and sky")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }
}

/// Convergence progress and live statistics. This is a separate view so the
/// rest of the panel doesn't re-render with every frame.
private struct PathTracerProgress: View {
    let model: PathTracerModel

    var body: some View {
        let stats = model.stats
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView(value: stats.progress)
                    .progressViewStyle(.linear)
                    .tint(Exhibit.pathTracer.tint)
                TagChip(text: stateTitle, tint: stateTint)
            }
            StatRow("Samples", "\(stats.samples.formatted()) / \(stats.targetSamples.formatted())")
            StatRow("Throughput", "\(PathTracerHUD.megarays(stats.raysPerSecond)) Mrays/s")
            StatRow("Resolution", "\(stats.width) × \(stats.height)")
        }
    }

    private var stateTitle: String {
        if model.stats.state == .converged { return "Converged" }
        return model.isPaused ? "Paused" : "Rendering"
    }

    private var stateTint: Color {
        if model.stats.state == .converged { return .green }
        return model.isPaused ? .orange : Exhibit.pathTracer.tint
    }
}

/// Pause/Resume, Restart and Save PNG. The buttons sit in one row when they
/// fit and stack when the panel is narrow.
private struct PathTracerRenderButtons: View {
    let model: PathTracerModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(alignment: .leading, spacing: 8) { buttons }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            model.togglePause()
        } label: {
            Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
        }
        .disabled(model.isConverged)

        Button {
            model.restart()
        } label: {
            Label("Restart", systemImage: "arrow.clockwise")
        }

        Button {
            model.savePNG()
        } label: {
            Label("Save PNG", systemImage: "square.and.arrow.down")
        }
        .disabled(!model.hasImage)
    }
}
