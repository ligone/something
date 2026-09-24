import Foundation

/// An attack–decay–sustain–release envelope with analog-style exponential segments.
///
/// Each segment is a one-pole filter chasing a target that lies slightly *beyond* the level it has
/// to reach (after Nigel Redmon's EarLevel ADSR). The curves look like an RC circuit charging and
/// discharging, yet every segment still finishes in exactly the requested time. Every segment also
/// starts from the current level, so retriggering a sounding note never jumps and never clicks.
public struct ADSREnvelope: Sendable {
    /// The segment the envelope is in.
    public enum Stage: Sendable, Equatable {
        case idle, attack, decay, sustain, release
    }

    /// Current segment.
    public private(set) var stage: Stage = .idle
    /// Current output, 0 … 1.
    public private(set) var level: Float = 0

    /// Attack time in seconds (from 0 to full level).
    public private(set) var attackTime: Double = 0.01
    /// Decay time in seconds (from full level to 0, were the sustain level 0).
    public private(set) var decayTime: Double = 0.2
    /// Sustain level, 0 … 1.
    public private(set) var sustainLevel: Double = 0.7
    /// Release time in seconds (from full level to 0).
    public private(set) var releaseTime: Double = 0.3
    /// Sample rate the coefficients were computed for.
    public private(set) var sampleRate: Double = 48_000

    private var attackCoefficient: Float = 0
    private var attackBase: Float = 0
    private var decayCoefficient: Float = 0
    private var decayBase: Float = 0
    private var releaseCoefficient: Float = 0
    private var releaseBase: Float = 0
    private var sustain: Float = 0.7
    private var sustainGlide: Float = 1

    /// Shortest attack; anything faster is heard as a click.
    public static let minimumAttack = 0.001
    /// Shortest decay.
    public static let minimumDecay = 0.002
    /// Shortest release.
    public static let minimumRelease = 0.003

    /// How far past its goal each segment aims: far for the attack (a gentle, nearly linear
    /// rise), very little for decay and release (a steep exponential that sounds even in dB).
    static let attackOvershoot = 0.3
    static let decayOvershoot = 0.000_1

    /// Creates an envelope; times are in seconds.
    public init(attack: Double = 0.01, decay: Double = 0.2, sustain: Double = 0.7, release: Double = 0.3, sampleRate: Double) {
        configure(attack: attack, decay: decay, sustain: sustain, release: release, sampleRate: sampleRate)
    }

    /// Updates the segment times and sustain level. Safe while running: the current segment simply
    /// continues from where it is at the new rate.
    public mutating func configure(attack: Double, decay: Double, sustain: Double, release: Double, sampleRate: Double) {
        let rate = sampleRate.isFinite ? max(sampleRate, 1) : 48_000
        self.sampleRate = rate
        attackTime = max(SynthMath.sanitize(attack, 0 ... 60, fallback: 0.01), Self.minimumAttack)
        decayTime = max(SynthMath.sanitize(decay, 0 ... 60, fallback: 0.2), Self.minimumDecay)
        sustainLevel = SynthMath.sanitize(sustain, 0 ... 1, fallback: 0.7)
        releaseTime = max(SynthMath.sanitize(release, 0 ... 60, fallback: 0.3), Self.minimumRelease)

        let a = Self.coefficient(samples: attackTime * rate, overshoot: Self.attackOvershoot)
        attackCoefficient = Float(a)
        attackBase = Float((1 + Self.attackOvershoot) * (1 - a))

        let d = Self.coefficient(samples: decayTime * rate, overshoot: Self.decayOvershoot)
        decayCoefficient = Float(d)
        decayBase = Float((sustainLevel - Self.decayOvershoot) * (1 - d))

        let r = Self.coefficient(samples: releaseTime * rate, overshoot: Self.decayOvershoot)
        releaseCoefficient = Float(r)
        releaseBase = Float(-Self.decayOvershoot * (1 - r))

        self.sustain = Float(sustainLevel)
        sustainGlide = Float(1 - exp(-1 / (0.005 * rate)))
    }

    /// Opens the gate: attack from the current level (no reset, so retriggers are seamless).
    public mutating func gateOn() {
        stage = .attack
    }

    /// Closes the gate: release from the current level.
    public mutating func gateOff() {
        if stage != .idle { stage = .release }
    }

    /// Silences the envelope immediately.
    public mutating func reset() {
        stage = .idle
        level = 0
    }

    /// Whether the envelope is producing output.
    public var isActive: Bool { stage != .idle }

    /// Advances one sample and returns the new level.
    @inline(__always)
    public mutating func next() -> Float {
        switch stage {
        case .idle:
            return 0
        case .attack:
            level = attackBase + level * attackCoefficient
            if level >= 1 {
                level = 1
                stage = .decay
            }
        case .decay:
            level = decayBase + level * decayCoefficient
            // Hand over to the sustain glide rather than snapping, in case sustain moved up.
            if level <= sustain { stage = .sustain }
        case .sustain:
            // A 5 ms glide lets the sustain level be dragged while a note is held without zipper
            // noise. It snaps once close, so a sustain of zero cannot decay into denormals.
            let difference = sustain - level
            level = abs(difference) < 1e-6 ? sustain : level + difference * sustainGlide
        case .release:
            level = releaseBase + level * releaseCoefficient
            if level <= 0 {
                level = 0
                stage = .idle
            }
        }
        return level
    }

    /// The one-pole coefficient that takes a segment from its start to within `overshoot` of its
    /// target in exactly `samples` steps.
    static func coefficient(samples: Double, overshoot: Double) -> Double {
        exp(-log((1 + overshoot) / overshoot) / max(samples, 1))
    }
}
