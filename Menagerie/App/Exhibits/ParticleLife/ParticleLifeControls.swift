import LifeKit
import SwiftUI

/// The control panel: the rules and their matrix, the particles, the
/// physics, the clock, and live statistics.
struct ParticleLifeControls: View {
    let model: ParticleLifeModel

    var body: some View {
        ControlSection("Rules") {
            VStack(alignment: .leading, spacing: 12) {
                presetPicker
                SpeciesMatrixEditor(model: model)
                HStack(spacing: 8) {
                    Button {
                        model.newRules()
                    } label: {
                        Label("New Rules", systemImage: "dice")
                    }
                    .help("Draw a random attraction matrix")
                    Button {
                        model.mutate()
                    } label: {
                        Label("Mutate", systemImage: "wand.and.stars")
                    }
                    .help("Nudge every entry a little, so the creatures morph")
                }
                Toggle("Symmetric", isOn: symmetric)
                    .toggleStyle(.switch)
                    .help("Every pair of species feels the same pull in both directions")
            }
        }

        ControlSection("Particles") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Species")
                    Picker("Species", selection: speciesCount) {
                        ForEach(ParticleLifeModel.speciesRange, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                ParameterSlider(
                    "Particles",
                    value: particleCount,
                    in: ParticleLifeModel.particleRange,
                    step: 100,
                    format: { Int($0).formatted() }
                )
                Button {
                    model.scatter()
                } label: {
                    Label("Scatter", systemImage: "shuffle")
                }
                .help("Throw every particle back into random noise and watch life re-form")
            }
        }

        ControlSection("Physics") {
            VStack(alignment: .leading, spacing: 12) {
                ParameterSlider(
                    "Interaction radius",
                    value: interactionRadius,
                    in: ParticleLifeModel.radiusRange,
                    format: { String(format: "%.3f", $0) }
                )
                ParameterSlider(
                    "Friction",
                    value: friction,
                    in: 0...1,
                    format: { friction in
                        let milliseconds = ParticleLifeModel.halfLife(forFriction: friction) * 1_000
                        return "\(Int(milliseconds.rounded())) ms half-life"
                    }
                )
                ParameterSlider(
                    "Force",
                    value: forceStrength,
                    in: ParticleLifeModel.forceRange,
                    format: { String(format: "%.1f", $0) }
                )
            }
        }

        ControlSection("Time") {
            VStack(alignment: .leading, spacing: 12) {
                ParameterSlider(
                    "Time scale",
                    value: timeScale,
                    in: ParticleLifeModel.timeScaleRange,
                    format: { String(format: "%.1f×", $0) }
                )
                HStack(spacing: 8) {
                    Button {
                        model.togglePause()
                    } label: {
                        Label(model.isPaused ? "Play" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    }
                    Button {
                        model.stepOnce()
                    } label: {
                        Label("Step", systemImage: "forward.frame.fill")
                    }
                    .disabled(!model.isPaused)
                    .help("Advance one sixtieth of a second while paused")
                }
            }
        }

        ControlSection("Statistics") {
            StatRow("Physics step", model.stepTimeText)
            StatRow("Simulated time", model.simulatedTimeText)
            StatRow("Mean speed", model.meanSpeedText)
        }
    }

    // MARK: - Pieces

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(LifePreset.all) { preset in
                    Button(preset.name) {
                        model.applyPreset(preset)
                    }
                }
            } label: {
                Label(model.presetTitle, systemImage: "sparkles")
            }
            .help("Rule sets known to grow something beautiful")
            Text(model.presetSummary ?? "Your own rules. Pick a preset to start from something known to be beautiful.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bindings

    private var symmetric: Binding<Bool> {
        Binding(get: { model.isSymmetric }, set: { model.setSymmetric($0) })
    }

    private var speciesCount: Binding<Int> {
        Binding(get: { model.speciesCount }, set: { model.setSpeciesCount($0) })
    }

    private var particleCount: Binding<Double> {
        Binding(get: { Double(model.particleCount) }, set: { model.setParticleCount($0) })
    }

    private var interactionRadius: Binding<Double> {
        Binding(get: { model.interactionRadius }, set: { model.setInteractionRadius($0) })
    }

    private var friction: Binding<Double> {
        Binding(get: { model.friction }, set: { model.setFriction($0) })
    }

    private var forceStrength: Binding<Double> {
        Binding(get: { model.forceStrength }, set: { model.setForceStrength($0) })
    }

    private var timeScale: Binding<Double> {
        Binding(get: { model.timeScale }, set: { model.setTimeScale($0) })
    }
}
