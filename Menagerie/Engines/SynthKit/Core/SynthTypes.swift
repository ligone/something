/// The shapes a SynthKit oscillator can produce.
public enum Waveform: String, CaseIterable, Codable, Sendable, Identifiable {
    /// A pure sine: the fundamental alone.
    case sine
    /// A triangle whose corners are rounded with PolyBLAMP, so it stays alias-free.
    case triangle
    /// A sawtooth with PolyBLEP-corrected resets: every harmonic, falling at 6 dB per octave.
    case sawtooth
    /// A PolyBLEP pulse with adjustable width; 50 % is a square wave with only odd harmonics.
    case pulse
    /// Seven detuned sawtooths, after the Roland JP-8000's "Super Saw".
    case supersaw
    /// White noise.
    case noise

    public var id: String { rawValue }

    /// A short human-readable name.
    public var displayName: String {
        switch self {
        case .sine: return "Sine"
        case .triangle: return "Triangle"
        case .sawtooth: return "Saw"
        case .pulse: return "Pulse"
        case .supersaw: return "Supersaw"
        case .noise: return "Noise"
        }
    }
}

/// Response of the voice filter.
public enum FilterMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Two-pole (12 dB/octave) low-pass.
    case lowPass12
    /// Four-pole (24 dB/octave) low-pass, two state-variable stages in series.
    case lowPass24
    /// Two-pole band-pass.
    case bandPass
    /// Two-pole high-pass.
    case highPass

    public var id: String { rawValue }

    /// A short label for a segmented control.
    public var displayName: String {
        switch self {
        case .lowPass12: return "LP 12"
        case .lowPass24: return "LP 24"
        case .bandPass: return "BP"
        case .highPass: return "HP"
        }
    }
}

/// Shape of the low-frequency oscillator.
public enum LFOShape: String, CaseIterable, Codable, Sendable, Identifiable {
    case sine
    case triangle

    public var id: String { rawValue }

    /// A short human-readable name.
    public var displayName: String {
        switch self {
        case .sine: return "Sine"
        case .triangle: return "Triangle"
        }
    }
}

/// Who started a note.
///
/// A note-off only releases voices started by the same source, so the generative sequencer and a
/// player can hold the same key without cutting each other off.
public enum SynthNoteSource: UInt8, Sendable {
    case player
    case sequencer
}

/// A set of MIDI notes (0 … 127) stored in two machine words, cheap to copy across threads.
public struct SynthNoteSet: Equatable, Hashable, Sendable {
    private var low: UInt64 = 0
    private var high: UInt64 = 0

    /// An empty set.
    public init() {}

    /// A set containing `notes` (out-of-range values are ignored).
    public init<S: Sequence>(_ notes: S) where S.Element == Int {
        for note in notes { insert(note) }
    }

    /// Whether `note` is in the set.
    @inline(__always)
    public func contains(_ note: Int) -> Bool {
        guard note >= 0, note < 128 else { return false }
        return note < 64 ? (low >> UInt64(note)) & 1 == 1 : (high >> UInt64(note - 64)) & 1 == 1
    }

    /// Adds `note` to the set.
    @inline(__always)
    public mutating func insert(_ note: Int) {
        guard note >= 0, note < 128 else { return }
        if note < 64 { low |= 1 << UInt64(note) } else { high |= 1 << UInt64(note - 64) }
    }

    /// Removes `note` from the set.
    @inline(__always)
    public mutating func remove(_ note: Int) {
        guard note >= 0, note < 128 else { return }
        if note < 64 { low &= ~(1 << UInt64(note)) } else { high &= ~(1 << UInt64(note - 64)) }
    }

    /// Removes every note.
    public mutating func removeAll() {
        low = 0
        high = 0
    }

    /// Number of notes in the set.
    public var count: Int { low.nonzeroBitCount + high.nonzeroBitCount }

    /// Whether the set is empty.
    public var isEmpty: Bool { low == 0 && high == 0 }

    /// The notes in ascending order.
    public var notes: [Int] { (0 ..< 128).filter { contains($0) } }
}
