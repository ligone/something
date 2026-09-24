/// Every sound-shaping parameter of the synthesizer, as a plain value.
///
/// A patch is a trivial (POD) struct: copying one is a `memcpy` with no reference counting. That is
/// what lets the audio thread take a new patch between blocks without touching the allocator.
/// Values outside the documented ranges are clamped by `sanitized()` before the engine uses them.
public struct SynthPatch: Equatable, Codable, Sendable {
    /// One of the two main oscillators.
    public struct Oscillator: Equatable, Codable, Sendable {
        public var waveform: Waveform
        /// Transposition in octaves, −2 … +2.
        public var octave: Int
        /// Fine tuning in cents, −50 … +50.
        public var detune: Double
        /// Duty cycle of `.pulse`, 0.05 … 0.95.
        public var pulseWidth: Double
        /// Detune spread of `.supersaw`, 0 … 1.
        public var spread: Double

        public static let octaveRange = -2 ... 2
        public static let detuneRange: ClosedRange<Double> = -50 ... 50
        public static let pulseWidthRange: ClosedRange<Double> = 0.05 ... 0.95
        public static let spreadRange: ClosedRange<Double> = 0 ... 1

        public init(waveform: Waveform, octave: Int = 0, detune: Double = 0, pulseWidth: Double = 0.5, spread: Double = 0.4) {
            self.waveform = waveform
            self.octave = octave
            self.detune = detune
            self.pulseWidth = pulseWidth
            self.spread = spread
        }
    }

    /// An ADSR envelope. Times are in seconds.
    public struct Envelope: Equatable, Codable, Sendable {
        public var attack: Double
        public var decay: Double
        /// Sustain level, 0 … 1.
        public var sustain: Double
        public var release: Double

        public static let attackRange: ClosedRange<Double> = 0.001 ... 10
        public static let decayRange: ClosedRange<Double> = 0.005 ... 10
        public static let sustainRange: ClosedRange<Double> = 0 ... 1
        public static let releaseRange: ClosedRange<Double> = 0.005 ... 12

        public init(attack: Double, decay: Double, sustain: Double, release: Double) {
            self.attack = attack
            self.decay = decay
            self.sustain = sustain
            self.release = release
        }
    }

    /// The voice filter and how it is modulated.
    public struct Filter: Equatable, Codable, Sendable {
        public var mode: FilterMode
        /// Cutoff in hertz, 20 … 20 000.
        public var cutoff: Double
        /// Resonance, 0 (none) … 1 (Q = 25).
        public var resonance: Double
        /// How far the filter envelope moves the cutoff, in octaves, −4 … +8.
        public var envelopeAmount: Double
        /// How closely the cutoff follows the keyboard, 0 … 1 (1 = one octave per octave).
        public var keyTracking: Double
        /// Extra cutoff at full velocity, in octaves, 0 … 4.
        public var velocityAmount: Double
        /// Saturation ahead of the filter, 0 … 1.
        public var drive: Double

        public static let cutoffRange: ClosedRange<Double> = 20 ... 20_000
        public static let resonanceRange: ClosedRange<Double> = 0 ... 1
        public static let envelopeAmountRange: ClosedRange<Double> = -4 ... 8
        public static let keyTrackingRange: ClosedRange<Double> = 0 ... 1
        public static let velocityAmountRange: ClosedRange<Double> = 0 ... 4
        public static let driveRange: ClosedRange<Double> = 0 ... 1

        public init(mode: FilterMode = .lowPass12, cutoff: Double, resonance: Double, envelopeAmount: Double, keyTracking: Double = 0.5, velocityAmount: Double = 0.5, drive: Double = 0.1) {
            self.mode = mode
            self.cutoff = cutoff
            self.resonance = resonance
            self.envelopeAmount = envelopeAmount
            self.keyTracking = keyTracking
            self.velocityAmount = velocityAmount
            self.drive = drive
        }
    }

    /// The low-frequency oscillator and its two destinations.
    public struct LFO: Equatable, Codable, Sendable {
        public var shape: LFOShape
        /// Rate in hertz, 0.05 … 20.
        public var rate: Double
        /// Vibrato depth in cents, 0 … 100.
        public var pitchDepth: Double
        /// Filter sweep depth in octaves, 0 … 4.
        public var cutoffDepth: Double

        public static let rateRange: ClosedRange<Double> = 0.05 ... 20
        public static let pitchDepthRange: ClosedRange<Double> = 0 ... 100
        public static let cutoffDepthRange: ClosedRange<Double> = 0 ... 4

        public init(shape: LFOShape = .sine, rate: Double, pitchDepth: Double, cutoffDepth: Double) {
            self.shape = shape
            self.rate = rate
            self.pitchDepth = pitchDepth
            self.cutoffDepth = cutoffDepth
        }
    }

    /// The master effects chain: chorus → ping-pong delay → reverb.
    public struct Effects: Equatable, Codable, Sendable {
        /// Chorus wet level, 0 … 1.
        public var chorusMix: Double
        /// Echo spacing in seconds, 0.02 … 1.5.
        public var delayTime: Double
        /// Echo feedback, 0 … 0.95.
        public var delayFeedback: Double
        /// Echo wet level, 0 … 1.
        public var delayMix: Double
        /// Reverb decay time (RT60) in seconds, 0.3 … 12.
        public var reverbDecay: Double
        /// High-frequency damping of the reverb tail, 0 (bright) … 1 (dark).
        public var reverbDamping: Double
        /// Reverb wet level, 0 … 1.
        public var reverbMix: Double

        public static let mixRange: ClosedRange<Double> = 0 ... 1
        public static let delayTimeRange: ClosedRange<Double> = 0.02 ... 1.5
        public static let delayFeedbackRange: ClosedRange<Double> = 0 ... 0.95
        public static let reverbDecayRange: ClosedRange<Double> = 0.3 ... 12
        public static let reverbDampingRange: ClosedRange<Double> = 0 ... 1

        public init(chorusMix: Double, delayTime: Double, delayFeedback: Double, delayMix: Double, reverbDecay: Double, reverbDamping: Double = 0.4, reverbMix: Double) {
            self.chorusMix = chorusMix
            self.delayTime = delayTime
            self.delayFeedback = delayFeedback
            self.delayMix = delayMix
            self.reverbDecay = reverbDecay
            self.reverbDamping = reverbDamping
            self.reverbMix = reverbMix
        }
    }

    public var osc1: Oscillator
    public var osc2: Oscillator
    /// Balance of the two oscillators: 0 = only osc 1, 1 = only osc 2.
    public var oscMix: Double
    /// Level of the square sub-oscillator one octave below osc 1, 0 … 1.
    public var subLevel: Double
    public var filter: Filter
    public var ampEnvelope: Envelope
    public var filterEnvelope: Envelope
    public var lfo: LFO
    /// How strongly key velocity scales loudness, 0 … 1.
    public var velocitySensitivity: Double
    /// How widely voices are spread across the stereo field, 0 … 1.
    public var stereoSpread: Double
    /// Output trim used to balance presets, 0 … 1.5.
    public var level: Double
    public var effects: Effects

    public static let unitRange: ClosedRange<Double> = 0 ... 1
    public static let levelRange: ClosedRange<Double> = 0 ... 1.5

    public init(
        osc1: Oscillator,
        osc2: Oscillator,
        oscMix: Double,
        subLevel: Double,
        filter: Filter,
        ampEnvelope: Envelope,
        filterEnvelope: Envelope,
        lfo: LFO,
        velocitySensitivity: Double = 0.5,
        stereoSpread: Double = 0.5,
        level: Double = 1,
        effects: Effects
    ) {
        self.osc1 = osc1
        self.osc2 = osc2
        self.oscMix = oscMix
        self.subLevel = subLevel
        self.filter = filter
        self.ampEnvelope = ampEnvelope
        self.filterEnvelope = filterEnvelope
        self.lfo = lfo
        self.velocitySensitivity = velocitySensitivity
        self.stereoSpread = stereoSpread
        self.level = level
        self.effects = effects
    }

    /// A copy with every value forced into its documented range; NaN and infinities become defaults.
    public func sanitized() -> SynthPatch {
        var p = self
        p.osc1 = osc1.sanitized()
        p.osc2 = osc2.sanitized()
        p.oscMix = SynthMath.sanitize(oscMix, Self.unitRange, fallback: 0.5)
        p.subLevel = SynthMath.sanitize(subLevel, Self.unitRange, fallback: 0)
        p.filter = filter.sanitized()
        p.ampEnvelope = ampEnvelope.sanitized()
        p.filterEnvelope = filterEnvelope.sanitized()
        p.lfo = lfo.sanitized()
        p.velocitySensitivity = SynthMath.sanitize(velocitySensitivity, Self.unitRange, fallback: 0.5)
        p.stereoSpread = SynthMath.sanitize(stereoSpread, Self.unitRange, fallback: 0.5)
        p.level = SynthMath.sanitize(level, Self.levelRange, fallback: 1)
        p.effects = effects.sanitized()
        return p
    }
}

extension SynthPatch.Oscillator {
    func sanitized() -> Self {
        var o = self
        o.octave = min(max(octave, Self.octaveRange.lowerBound), Self.octaveRange.upperBound)
        o.detune = SynthMath.sanitize(detune, Self.detuneRange, fallback: 0)
        o.pulseWidth = SynthMath.sanitize(pulseWidth, Self.pulseWidthRange, fallback: 0.5)
        o.spread = SynthMath.sanitize(spread, Self.spreadRange, fallback: 0.4)
        return o
    }
}

extension SynthPatch.Envelope {
    func sanitized() -> Self {
        Self(
            attack: SynthMath.sanitize(attack, Self.attackRange, fallback: 0.01),
            decay: SynthMath.sanitize(decay, Self.decayRange, fallback: 0.3),
            sustain: SynthMath.sanitize(sustain, Self.sustainRange, fallback: 0.7),
            release: SynthMath.sanitize(release, Self.releaseRange, fallback: 0.4)
        )
    }
}

extension SynthPatch.Filter {
    func sanitized() -> Self {
        var f = self
        f.cutoff = SynthMath.sanitize(cutoff, Self.cutoffRange, fallback: 2_000)
        f.resonance = SynthMath.sanitize(resonance, Self.resonanceRange, fallback: 0.2)
        f.envelopeAmount = SynthMath.sanitize(envelopeAmount, Self.envelopeAmountRange, fallback: 0)
        f.keyTracking = SynthMath.sanitize(keyTracking, Self.keyTrackingRange, fallback: 0.5)
        f.velocityAmount = SynthMath.sanitize(velocityAmount, Self.velocityAmountRange, fallback: 0)
        f.drive = SynthMath.sanitize(drive, Self.driveRange, fallback: 0)
        return f
    }
}

extension SynthPatch.LFO {
    func sanitized() -> Self {
        var l = self
        l.rate = SynthMath.sanitize(rate, Self.rateRange, fallback: 1)
        l.pitchDepth = SynthMath.sanitize(pitchDepth, Self.pitchDepthRange, fallback: 0)
        l.cutoffDepth = SynthMath.sanitize(cutoffDepth, Self.cutoffDepthRange, fallback: 0)
        return l
    }
}

extension SynthPatch.Effects {
    func sanitized() -> Self {
        Self(
            chorusMix: SynthMath.sanitize(chorusMix, Self.mixRange, fallback: 0),
            delayTime: SynthMath.sanitize(delayTime, Self.delayTimeRange, fallback: 0.35),
            delayFeedback: SynthMath.sanitize(delayFeedback, Self.delayFeedbackRange, fallback: 0.3),
            delayMix: SynthMath.sanitize(delayMix, Self.mixRange, fallback: 0),
            reverbDecay: SynthMath.sanitize(reverbDecay, Self.reverbDecayRange, fallback: 2),
            reverbDamping: SynthMath.sanitize(reverbDamping, Self.reverbDampingRange, fallback: 0.4),
            reverbMix: SynthMath.sanitize(reverbMix, Self.mixRange, fallback: 0)
        )
    }
}
