import SwiftUI
import SynthKit

// The control panel, one design-system `ControlSection` per stage of the signal path.

/// "Play me something", tempo and volume.
struct SynthPlaySection: View {
    @Bindable var model: SynthesizerModel

    var body: some View {
        ControlSection("Play") {
            SynthPlayButton(isPlaying: model.isPlayingSomething) {
                model.togglePlayMeSomething()
            }
            ParameterSlider("Tempo", value: $model.tempo, in: SynthSequencer.tempoRange, step: 1, format: SynthFormat.tempo)
            ParameterSlider("Volume", value: $model.masterVolume, in: 0 ... 1, format: SynthFormat.percent)
        }
    }
}

/// The factory sounds, as a grid of buttons.
struct SynthPresetSection: View {
    let model: SynthesizerModel

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ControlSection("Preset") {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SynthPreset.all) { preset in
                    presetButton(preset)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Text(model.currentPreset.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if model.isPatchEdited {
                    TagChip(text: "Edited", tint: SynthPalette.accent)
                    Button("Revert") { model.revertToPreset() }
                        .controlSize(.small)
                }
            }
        }
    }

    private func presetButton(_ preset: SynthPreset) -> some View {
        let isSelected = preset.id == model.presetID
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button {
            model.selectPreset(preset.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(for: preset.id))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? SynthPalette.accent : Color.secondary)
                Text(preset.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? SynthPalette.accent.opacity(0.18) : Color.primary.opacity(0.06), in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? SynthPalette.accent.opacity(0.9) : Color.clear, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(preset.summary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func symbol(for presetID: String) -> String {
        switch presetID {
        case SynthPreset.glassKeys.id: return "sparkles"
        case SynthPreset.warmPad.id: return "cloud"
        case SynthPreset.pluck.id: return "drop"
        case SynthPreset.supersawLead.id: return "bolt"
        case SynthPreset.acidBass.id: return "waveform.path"
        default: return "waveform"
        }
    }
}

/// Two oscillators, their balance and the sub-oscillator.
struct SynthOscillatorSection: View {
    @Bindable var model: SynthesizerModel

    var body: some View {
        ControlSection("Oscillators") {
            SynthOscillatorControls(title: "Oscillator 1", settings: $model.patch.osc1)
            Divider()
            SynthOscillatorControls(title: "Oscillator 2", settings: $model.patch.osc2)
            Divider()
            ParameterSlider("Mix 1 : 2", value: $model.patch.oscMix, in: SynthPatch.unitRange, format: SynthFormat.balance)
            ParameterSlider("Sub oscillator", value: $model.patch.subLevel, in: SynthPatch.unitRange, format: SynthFormat.percent)
        }
    }
}

/// Waveform, octave, detune and the shape control that belongs to the waveform.
struct SynthOscillatorControls: View {
    let title: String
    @Binding var settings: SynthPatch.Oscillator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Picker("Octave", selection: $settings.octave) {
                    ForEach(Array(SynthPatch.Oscillator.octaveRange), id: \.self) { octave in
                        Text(octave > 0 ? "+\(octave)" : "\(octave)").tag(octave)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 170)
                .help("Octave")
            }
            SynthWaveformPicker(selection: $settings.waveform)
            ParameterSlider("Detune", value: $settings.detune, in: SynthPatch.Oscillator.detuneRange, step: 1, format: SynthFormat.cents)
            if settings.waveform == .pulse {
                ParameterSlider("Pulse width", value: $settings.pulseWidth, in: SynthPatch.Oscillator.pulseWidthRange, format: SynthFormat.percent)
            } else if settings.waveform == .supersaw {
                ParameterSlider("Spread", value: $settings.spread, in: SynthPatch.Oscillator.spreadRange, format: SynthFormat.percent)
            }
        }
    }
}

/// Filter mode, response curve, cutoff, resonance and modulation amounts.
struct SynthFilterSection: View {
    @Bindable var model: SynthesizerModel

    var body: some View {
        ControlSection("Filter") {
            Picker("Mode", selection: $model.patch.filter.mode) {
                ForEach(FilterMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            SynthFilterResponseView(filter: $model.patch.filter, sampleRate: model.sampleRate)
            ParameterSlider("Cutoff", value: $model.cutoffPosition, in: 0 ... 1, format: { SynthFormat.frequency(LogScale.cutoff.value(at: $0)) })
            ParameterSlider("Resonance", value: $model.patch.filter.resonance, in: SynthPatch.Filter.resonanceRange, format: SynthFormat.percent)
            ParameterSlider("Envelope amount", value: $model.patch.filter.envelopeAmount, in: SynthPatch.Filter.envelopeAmountRange, format: SynthFormat.octaves)
            ParameterSlider("Key tracking", value: $model.patch.filter.keyTracking, in: SynthPatch.Filter.keyTrackingRange, format: SynthFormat.percent)
            ParameterSlider("Drive", value: $model.patch.filter.drive, in: SynthPatch.Filter.driveRange, format: SynthFormat.percent)
        }
    }
}

/// The amplitude and filter envelopes, edited on a graph.
struct SynthEnvelopeSection: View {
    @Bindable var model: SynthesizerModel
    @State private var showsFilterEnvelope = false

    var body: some View {
        ControlSection("Envelopes") {
            Picker("Envelope", selection: $showsFilterEnvelope) {
                Text("Amplitude").tag(false)
                Text("Filter").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if showsFilterEnvelope {
                SynthEnvelopeEditor(envelope: $model.patch.filterEnvelope, tint: SynthPalette.violet)
            } else {
                SynthEnvelopeEditor(envelope: $model.patch.ampEnvelope, tint: SynthPalette.accent)
            }
        }
    }
}

/// The LFO's shape, rate and two destinations.
struct SynthModulationSection: View {
    @Bindable var model: SynthesizerModel

    var body: some View {
        ControlSection("LFO") {
            Picker("Shape", selection: $model.patch.lfo.shape) {
                ForEach(LFOShape.allCases) { shape in
                    Text(shape.displayName).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ParameterSlider("Rate", value: $model.lfoRatePosition, in: 0 ... 1, format: { SynthFormat.rate(LogScale.lfoRate.value(at: $0)) })
            ParameterSlider("Vibrato depth", value: $model.patch.lfo.pitchDepth, in: SynthPatch.LFO.pitchDepthRange, step: 1, format: { String(format: "%.0f ct", $0) })
            ParameterSlider("Filter sweep depth", value: $model.patch.lfo.cutoffDepth, in: SynthPatch.LFO.cutoffDepthRange, format: { String(format: "%.1f oct", $0) })
        }
    }
}

/// Chorus, ping-pong delay, reverb and stereo width.
struct SynthEffectsSection: View {
    @Bindable var model: SynthesizerModel

    var body: some View {
        ControlSection("Effects") {
            ParameterSlider("Chorus", value: $model.patch.effects.chorusMix, in: SynthPatch.Effects.mixRange, format: SynthFormat.percent)
            ParameterSlider("Delay mix", value: $model.patch.effects.delayMix, in: SynthPatch.Effects.mixRange, format: SynthFormat.percent)
            ParameterSlider("Delay time", value: $model.delayTimePosition, in: 0 ... 1, format: { SynthFormat.time(LogScale.delayTime.value(at: $0)) })
            ParameterSlider("Delay feedback", value: $model.patch.effects.delayFeedback, in: SynthPatch.Effects.delayFeedbackRange, format: SynthFormat.percent)
            ParameterSlider("Reverb mix", value: $model.patch.effects.reverbMix, in: SynthPatch.Effects.mixRange, format: SynthFormat.percent)
            ParameterSlider("Reverb decay", value: $model.reverbDecayPosition, in: 0 ... 1, format: { SynthFormat.time(LogScale.reverbDecay.value(at: $0)) })
            ParameterSlider("Stereo width", value: $model.patch.stereoSpread, in: SynthPatch.unitRange, format: SynthFormat.percent)
        }
    }
}

/// The big "Play me something" toggle.
struct SynthPlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(isPlaying ? "Stop playing" : "Play me something")
                        .font(.headline)
                    Text(isPlaying ? "Composing as it goes" : "Generative ambient music")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 4)
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(
                colors: [Color(red: 0.06, green: 0.45, blue: 0.72), Color(red: 0.38, green: 0.25, blue: 0.84)],
                startPoint: .leading,
                endPoint: .trailing
            ), in: shape)
            .shadow(color: SynthPalette.accent.opacity(isPlaying ? 0.5 : 0.18), radius: isPlaying ? 10 : 4)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
        .accessibilityLabel(isPlaying ? "Stop playing" : "Play me something")
    }
}
