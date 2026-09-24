import Foundation

/// Control-rate values shared by every voice, computed once per tick by the renderer.
struct VoiceParameters {
    var sampleRate: Float = 48_000
    /// Samples between control ticks; ramps are spread over this many samples.
    var controlInterval: Float = 16
    /// Transposition of each oscillator in semitones (octave · 12 + cents ÷ 100).
    var osc1Semitones: Float = 0
    var osc2Semitones: Float = 0
    /// Current vibrato offset in semitones.
    var vibratoSemitones: Float = 0
    /// Base cutoff as log₂(hertz).
    var cutoffOctaves: Float = 11
    var envelopeAmount: Float = 0
    var keyTracking: Float = 0
    var velocityAmount: Float = 0
    /// Current LFO filter sweep in octaves.
    var lfoCutoffOctaves: Float = 0
    /// Damping `k` of the resonant filter stage.
    var damping: Float = 2
    var mode: FilterMode = .lowPass12
    var osc1Gain: Float = 1
    var osc2Gain: Float = 0
    var subGain: Float = 0
    /// Gain into the pre-filter saturator, and the makeup gain after it.
    var drive: Float = 0.5
    var driveMakeup: Float = 1
    /// Final per-voice gain (patch level times headroom).
    var outputGain: Float = 0.25
}

/// One voice of the polyphonic synthesizer: two oscillators and a sub, a drive stage, the TPT
/// state-variable filter, and amp and filter envelopes.
///
/// Pitch and cutoff are computed at control rate (`updateControl`) and reach the audio loop as
/// per-sample linear ramps, which keeps the expensive `exp2` and `tan` calls out of the inner loop
/// without audible stepping.
struct SynthVoice {
    enum State: UInt8 {
        /// Silent and available.
        case idle
        /// Key down.
        case held
        /// Key up; the release tail is still sounding.
        case released
        /// Fading out quickly so the voice can be reused for `pendingNote`.
        case stealing
    }

    /// Largest block a voice renders at once (the control interval).
    static let maxChunk = 16
    /// Resonance saturation limit of the band-pass integrator.
    private static var resonanceLimit: Float { 3 }

    var state: State = .idle
    var note = 60
    var source: SynthNoteSource = .player
    var velocity: Float = 1
    /// Age stamp; the smallest value is the oldest note.
    var age: UInt64 = 0

    private var velocityGain: Float = 1
    private var velocityGainTarget: Float = 1
    private var panLeft: Float = 0.707
    private var panRight: Float = 0.707

    private var osc1: SynthOscillator
    private var osc2: SynthOscillator
    private var sub: SynthOscillator
    private var filterA = SVFilter()
    private var filterB = SVFilter()
    private(set) var ampEnvelope: ADSREnvelope
    private(set) var filterEnvelope: ADSREnvelope

    private var increment1: Float = 0
    private var increment1Step: Float = 0
    private var increment2: Float = 0
    private var increment2Step: Float = 0
    private var filterGain: Float = 0.1
    private var filterGainStep: Float = 0

    private(set) var fade: Float = 1
    private var fadeStep: Float = 0
    private(set) var pendingNote = 60
    private(set) var pendingVelocity: Float = 1
    private(set) var pendingSource: SynthNoteSource = .player
    var pendingReleased = false

    init(seed: UInt32, sampleRate: Double) {
        osc1 = SynthOscillator(waveform: .sawtooth, seed: seed)
        osc2 = SynthOscillator(waveform: .sawtooth, seed: seed &* 747_796_405 &+ 1)
        sub = SynthOscillator(waveform: .pulse, pulseWidth: 0.5, seed: seed &* 2_891_336_453 &+ 7)
        ampEnvelope = ADSREnvelope(sampleRate: sampleRate)
        filterEnvelope = ADSREnvelope(sampleRate: sampleRate)
    }

    /// Whether the voice is gated by a held key (or is about to be, once its steal fade ends).
    var isGated: Bool {
        state == .held || (state == .stealing && !pendingReleased)
    }

    /// The note the voice is playing or about to play.
    var effectiveNote: Int {
        state == .stealing ? pendingNote : note
    }

    // MARK: - Patch

    /// Applies the patch settings that live inside the voice.
    mutating func configure(_ patch: SynthPatch, sampleRate: Double) {
        osc1.waveform = patch.osc1.waveform
        osc1.pulseWidth = Float(patch.osc1.pulseWidth)
        osc1.spread = Float(patch.osc1.spread)
        osc2.waveform = patch.osc2.waveform
        osc2.pulseWidth = Float(patch.osc2.pulseWidth)
        osc2.spread = Float(patch.osc2.spread)
        let amp = patch.ampEnvelope
        ampEnvelope.configure(attack: amp.attack, decay: amp.decay, sustain: amp.sustain, release: amp.release, sampleRate: sampleRate)
        let flt = patch.filterEnvelope
        filterEnvelope.configure(attack: flt.attack, decay: flt.decay, sustain: flt.sustain, release: flt.release, sampleRate: sampleRate)
    }

    // MARK: - Notes

    /// Starts a note from silence.
    mutating func start(note: Int, velocity: Float, source: SynthNoteSource, age: UInt64, sensitivity: Float, pan: Float, parameters: VoiceParameters) {
        state = .held
        self.note = note
        self.source = source
        self.velocity = velocity
        self.age = age
        velocityGainTarget = Self.velocityGain(velocity, sensitivity: sensitivity)
        velocityGain = velocityGainTarget
        (panLeft, panRight) = SynthMath.panGains(pan)
        osc1.reset()
        osc2.reset()
        sub.reset()
        filterA.reset()
        filterB.reset()
        ampEnvelope.reset()
        filterEnvelope.reset()
        ampEnvelope.gateOn()
        filterEnvelope.gateOn()
        fade = 1
        fadeStep = 0
        pendingReleased = false
        updateControl(parameters, immediate: true)
    }

    /// Strikes the note again. Envelopes restart from their current level and oscillators keep
    /// their phase, so nothing jumps; the velocity gain glides to its new value.
    mutating func retrigger(velocity: Float, age: UInt64, sensitivity: Float) {
        state = .held
        self.velocity = velocity
        self.age = age
        velocityGainTarget = Self.velocityGain(velocity, sensitivity: sensitivity)
        ampEnvelope.gateOn()
        filterEnvelope.gateOn()
    }

    /// Lets go of the key.
    mutating func release() {
        guard state == .held else { return }
        state = .released
        ampEnvelope.gateOff()
        filterEnvelope.gateOff()
    }

    /// Begins a short fade-out, after which the renderer restarts the voice on `note`.
    mutating func beginSteal(note: Int, velocity: Float, source: SynthNoteSource, fadeSamples: Int) {
        if state != .stealing {
            state = .stealing
            fadeStep = fade / Float(max(fadeSamples, 1))
        }
        pendingNote = note
        pendingVelocity = velocity
        pendingSource = source
        pendingReleased = false
    }

    /// Whether a steal fade has finished and the pending note should start.
    var isReadyToStartPendingNote: Bool {
        state == .stealing && fade <= 0
    }

    /// Silences the voice immediately.
    mutating func kill() {
        state = .idle
        ampEnvelope.reset()
        filterEnvelope.reset()
        fade = 1
        fadeStep = 0
    }

    // MARK: - Rendering

    /// Recomputes pitch and cutoff targets. With `immediate`, jumps straight to them (note start);
    /// otherwise sets ramps that arrive exactly one control interval later.
    mutating func updateControl(_ p: VoiceParameters, immediate: Bool) {
        let key = Float(note)
        let target1 = SynthOscillator.clampIncrement(Self.increment(key + p.osc1Semitones + p.vibratoSemitones, p.sampleRate))
        let target2 = SynthOscillator.clampIncrement(Self.increment(key + p.osc2Semitones + p.vibratoSemitones, p.sampleRate))

        var octaves = p.cutoffOctaves
        octaves += p.envelopeAmount * filterEnvelope.level
        octaves += p.keyTracking * (key - 60) / 12
        octaves += p.velocityAmount * velocity
        octaves += p.lfoCutoffOctaves
        octaves = min(max(octaves, 3), 15)
        let targetGain = SVFilter.gain(cutoff: exp2(octaves), sampleRate: p.sampleRate)

        if immediate {
            increment1 = target1
            increment2 = target2
            filterGain = targetGain
            increment1Step = 0
            increment2Step = 0
            filterGainStep = 0
        } else {
            let inverse = 1 / p.controlInterval
            increment1Step = (target1 - increment1) * inverse
            increment2Step = (target2 - increment2) * inverse
            filterGainStep = (targetGain - filterGain) * inverse
        }
    }

    /// Adds `count` (≤ `maxChunk`) samples of this voice to the stereo mix.
    ///
    /// - Parameter scratch: At least `3 × maxChunk` floats of workspace.
    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int, parameters p: VoiceParameters, scratch: UnsafeMutablePointer<Float>) {
        guard state != .idle, count > 0 else { return }
        let n = min(count, Self.maxChunk)
        let s1 = scratch
        let s2 = scratch + Self.maxChunk
        let s3 = scratch + 2 * Self.maxChunk

        osc1.render(into: s1, count: n, increment: increment1, incrementStep: increment1Step)
        if p.osc2Gain > 1e-4 {
            osc2.render(into: s2, count: n, increment: increment2, incrementStep: increment2Step)
        } else {
            s2.update(repeating: 0, count: n)
        }
        if p.subGain > 1e-4 {
            sub.render(into: s3, count: n, increment: increment1 * 0.5, incrementStep: increment1Step * 0.5)
        } else {
            s3.update(repeating: 0, count: n)
        }
        increment1 += increment1Step * Float(n)
        increment2 += increment2Step * Float(n)

        // Work on local copies so the inner loop touches registers, not `self`.
        var fa = filterA
        var fb = filterB
        var amp = ampEnvelope
        var fenv = filterEnvelope
        var g = filterGain
        var vGain = velocityGain
        var fadeLevel = fade
        let gStep = filterGainStep
        let vTarget = velocityGainTarget
        let fStep = fadeStep
        let k = p.damping
        let k1 = SVFilter.fourPoleFirstStageDamping
        let limit = Self.resonanceLimit
        let g1 = p.osc1Gain
        let g2 = p.osc2Gain
        let g3 = p.subGain
        let pre = p.drive
        let makeup = p.driveMakeup
        let out = p.outputGain
        let pl = panLeft
        let pr = panRight
        let mode = p.mode

        for i in 0 ..< n {
            let mix = s1[i] * g1 + s2[i] * g2 + s3[i] * g3
            let x = SynthMath.softSaturate(mix * pre) * makeup
            g += gStep
            let y: Float
            switch mode {
            case .lowPass12:
                y = fa.process(x, g: g, k: k).lowPass
                fa.saturateResonance(limit: limit)
            case .lowPass24:
                let firstStage = fa.process(x, g: g, k: k1).lowPass
                y = fb.process(firstStage, g: g, k: k).lowPass
                fb.saturateResonance(limit: limit)
            case .bandPass:
                y = fa.process(x, g: g, k: k).bandPass
                fa.saturateResonance(limit: limit)
            case .highPass:
                y = fa.process(x, g: g, k: k).highPass
                fa.saturateResonance(limit: limit)
            }
            let envelope = amp.next()
            _ = fenv.next()
            vGain += (vTarget - vGain) * 0.01
            fadeLevel = max(fadeLevel - fStep, 0)
            let v = y * envelope * vGain * fadeLevel * out
            left[i] += v * pl
            right[i] += v * pr
        }

        filterA = fa
        filterB = fb
        ampEnvelope = amp
        filterEnvelope = fenv
        filterGain = g
        velocityGain = vGain
        fade = fadeLevel
        if state == .released && !amp.isActive {
            state = .idle
        }
    }

    // MARK: - Helpers

    @inline(__always)
    private static func increment(_ pitch: Float, _ sampleRate: Float) -> Float {
        440 * exp2((pitch - 69) / 12) / sampleRate
    }

    /// Loudness for a velocity: a square law (closer to perceived dynamics than linear), blended
    /// with full level by the patch's sensitivity.
    private static func velocityGain(_ velocity: Float, sensitivity: Float) -> Float {
        let v = min(max(velocity, 0), 1)
        return 1 - sensitivity + sensitivity * v * v
    }
}
