import AppKit
import Combine
import SwiftUI
import SynthKit

/// The Synthesizer exhibit: an eight-voice polyphonic synthesizer written from scratch, with a
/// live oscilloscope and spectrum analyzer on stage and every parameter in the control panel.
struct SynthesizerExhibit: View {
    @State private var model = SynthesizerModel()

    var body: some View {
        ExhibitLayout(.synthesizer) {
            SynthStageView(model: model)
                .stageHUD { SynthStageHUD(model: model) }
                .stageHint("Play with A–K on your keyboard · Z/X change octave")
        } controls: {
            SynthPlaySection(model: model)
            SynthPresetSection(model: model)
            SynthOscillatorSection(model: model)
            SynthFilterSection(model: model)
            SynthEnvelopeSection(model: model)
            SynthModulationSection(model: model)
            SynthEffectsSection(model: model)
        }
        .onAppear { model.activate() }
        .onDisappear { model.deactivate() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // Key-up events never arrive while another app is active; let go now.
            model.releaseHeldNotes()
        }
    }
}

/// Live engine readouts over the stage.
struct SynthStageHUD: View {
    let model: SynthesizerModel

    var body: some View {
        HStack(spacing: 8) {
            StatPill("Voices", "\(model.status.activeVoices)/\(SynthEngine.polyphony)")
            StatPill("Sample rate", SynthFormat.sampleRate(model.sampleRate))
            StatPill("CPU", SynthFormat.load(model.status.cpuLoad))
            if model.status.isSequencerPlaying, let chord = model.status.chord {
                StatPill("Chord", chord.name)
            }
        }
    }
}
