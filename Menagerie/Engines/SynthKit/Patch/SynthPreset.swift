/// A named, ready-made patch.
public struct SynthPreset: Identifiable, Equatable, Sendable {
    /// Stable identifier, suitable for persistence.
    public let id: String
    /// Display name.
    public let name: String
    /// One-line description of the sound.
    public let summary: String
    /// The sound itself.
    public let patch: SynthPatch

    public init(id: String, name: String, summary: String, patch: SynthPatch) {
        self.id = id
        self.name = name
        self.summary = summary
        self.patch = patch
    }

    /// Every factory preset, in display order.
    public static let all: [SynthPreset] = [glassKeys, warmPad, pluck, supersawLead, acidBass]

    /// The preset loaded when the synthesizer opens.
    public static var `default`: SynthPreset { glassKeys }

    /// Looks up a factory preset by identifier.
    public static func named(_ id: String) -> SynthPreset? {
        all.first { $0.id == id }
    }

    /// Triangle plus a sine two octaves up, through a filter that closes as the note decays, so the
    /// bright upper partial fades first like a struck glass or a tine.
    public static let glassKeys = SynthPreset(
        id: "glass-keys",
        name: "Glass Keys",
        summary: "Bell-like electric piano with a shimmering tail",
        patch: SynthPatch(
            osc1: .init(waveform: .triangle),
            osc2: .init(waveform: .sine, octave: 2, detune: 4),
            oscMix: 0.34,
            subLevel: 0,
            filter: .init(mode: .lowPass12, cutoff: 1_800, resonance: 0.28, envelopeAmount: 2.6, keyTracking: 0.7, velocityAmount: 0.8, drive: 0.1),
            ampEnvelope: .init(attack: 0.002, decay: 2.2, sustain: 0.18, release: 1.1),
            filterEnvelope: .init(attack: 0.001, decay: 0.9, sustain: 0.2, release: 0.8),
            lfo: .init(shape: .sine, rate: 4.5, pitchDepth: 0, cutoffDepth: 0),
            velocitySensitivity: 0.65,
            stereoSpread: 0.55,
            level: 1.4,
            effects: .init(chorusMix: 0.45, delayTime: 0.36, delayFeedback: 0.32, delayMix: 0.18, reverbDecay: 3.2, reverbDamping: 0.35, reverbMix: 0.3)
        )
    )

    /// Two sawtooths a few cents apart plus a sub, a slow four-pole filter swell, chorus and a long
    /// dark reverb.
    public static let warmPad = SynthPreset(
        id: "warm-pad",
        name: "Warm Pad",
        summary: "Slow, breathing analog strings",
        patch: SynthPatch(
            osc1: .init(waveform: .sawtooth, detune: -6),
            osc2: .init(waveform: .sawtooth, detune: 6),
            oscMix: 0.5,
            subLevel: 0.25,
            filter: .init(mode: .lowPass24, cutoff: 1_100, resonance: 0.18, envelopeAmount: 1.2, keyTracking: 0.4, velocityAmount: 0.3, drive: 0.15),
            ampEnvelope: .init(attack: 0.8, decay: 1.8, sustain: 0.85, release: 3.2),
            filterEnvelope: .init(attack: 1.4, decay: 2.6, sustain: 0.45, release: 3),
            lfo: .init(shape: .triangle, rate: 0.18, pitchDepth: 3, cutoffDepth: 0.35),
            velocitySensitivity: 0.35,
            stereoSpread: 0.85,
            level: 1,
            effects: .init(chorusMix: 0.75, delayTime: 0.48, delayFeedback: 0.38, delayMix: 0.14, reverbDecay: 5.5, reverbDamping: 0.55, reverbMix: 0.42)
        )
    )

    /// A pulse and a sawtooth snapped open by a fast filter envelope, like a plucked string.
    public static let pluck = SynthPreset(
        id: "pluck",
        name: "Pluck",
        summary: "Snappy harp-like pluck with echoes",
        patch: SynthPatch(
            osc1: .init(waveform: .pulse, pulseWidth: 0.32),
            osc2: .init(waveform: .sawtooth, detune: -7),
            oscMix: 0.45,
            subLevel: 0.12,
            filter: .init(mode: .lowPass12, cutoff: 520, resonance: 0.32, envelopeAmount: 4.2, keyTracking: 0.75, velocityAmount: 1, drive: 0.2),
            ampEnvelope: .init(attack: 0.001, decay: 0.9, sustain: 0, release: 0.45),
            filterEnvelope: .init(attack: 0.001, decay: 0.28, sustain: 0, release: 0.3),
            lfo: .init(shape: .sine, rate: 0.3, pitchDepth: 0, cutoffDepth: 0),
            velocitySensitivity: 0.55,
            stereoSpread: 0.65,
            level: 1.1,
            effects: .init(chorusMix: 0.35, delayTime: 0.3, delayFeedback: 0.36, delayMix: 0.22, reverbDecay: 2.4, reverbDamping: 0.45, reverbMix: 0.26)
        )
    )

    /// Seven detuned sawtooths with a sawtooth an octave up, a sub, and a singer's vibrato from
    /// the LFO.
    public static let supersawLead = SynthPreset(
        id: "supersaw-lead",
        name: "Supersaw Lead",
        summary: "Wide trance lead with vibrato",
        patch: SynthPatch(
            osc1: .init(waveform: .supersaw, spread: 0.42),
            osc2: .init(waveform: .sawtooth, octave: 1, detune: 5),
            oscMix: 0.22,
            subLevel: 0.28,
            filter: .init(mode: .lowPass12, cutoff: 2_800, resonance: 0.2, envelopeAmount: 1.2, keyTracking: 0.5, velocityAmount: 0.6, drive: 0.25),
            ampEnvelope: .init(attack: 0.006, decay: 0.3, sustain: 0.88, release: 0.38),
            filterEnvelope: .init(attack: 0.004, decay: 0.5, sustain: 0.55, release: 0.35),
            lfo: .init(shape: .sine, rate: 5.6, pitchDepth: 9, cutoffDepth: 0),
            velocitySensitivity: 0.35,
            stereoSpread: 0.3,
            level: 0.9,
            effects: .init(chorusMix: 0.2, delayTime: 0.375, delayFeedback: 0.42, delayMix: 0.24, reverbDecay: 2.8, reverbDamping: 0.4, reverbMix: 0.26)
        )
    )

    /// A resonant, driven sawtooth an octave down whose filter envelope and velocity do all the
    /// talking, in the spirit of the TB-303.
    public static let acidBass = SynthPreset(
        id: "acid-bass",
        name: "Acid Bass",
        summary: "Squelchy resonant bass; velocity opens the filter",
        patch: SynthPatch(
            osc1: .init(waveform: .sawtooth, octave: -1),
            osc2: .init(waveform: .pulse, octave: -1, detune: 3, pulseWidth: 0.5),
            oscMix: 0.15,
            subLevel: 0.3,
            filter: .init(mode: .lowPass12, cutoff: 240, resonance: 0.8, envelopeAmount: 4, keyTracking: 0.35, velocityAmount: 1, drive: 0.55),
            ampEnvelope: .init(attack: 0.002, decay: 0.45, sustain: 0.75, release: 0.08),
            filterEnvelope: .init(attack: 0.001, decay: 0.22, sustain: 0, release: 0.12),
            lfo: .init(shape: .sine, rate: 0.2, pitchDepth: 0, cutoffDepth: 0),
            velocitySensitivity: 0.4,
            stereoSpread: 0.05,
            level: 0.75,
            effects: .init(chorusMix: 0, delayTime: 0.21, delayFeedback: 0.28, delayMix: 0.12, reverbDecay: 1.4, reverbDamping: 0.5, reverbMix: 0.1)
        )
    )
}
