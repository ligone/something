/// Chord qualities the generative sequencer plays: extended, "lush" harmony.
public enum SynthChordQuality: Int, CaseIterable, Sendable {
    case minor7, minor9, minor11, major7, major9, add9, sixNine, major7Sharp11

    /// Suffix for a chord symbol, e.g. "m9".
    public var suffix: String {
        switch self {
        case .minor7: return "m7"
        case .minor9: return "m9"
        case .minor11: return "m11"
        case .major7: return "maj7"
        case .major9: return "maj9"
        case .add9: return "add9"
        case .sixNine: return "6/9"
        case .major7Sharp11: return "maj7♯11"
        }
    }

    /// Chord tones in semitones above the root; lanes past `toneCount` are unused.
    var tones: SIMD8<Int32> {
        switch self {
        case .minor7: return SIMD8(0, 3, 7, 10, 0, 0, 0, 0)
        case .minor9: return SIMD8(0, 3, 7, 10, 14, 0, 0, 0)
        case .minor11: return SIMD8(0, 3, 7, 10, 14, 17, 0, 0)
        case .major7: return SIMD8(0, 4, 7, 11, 0, 0, 0, 0)
        case .major9: return SIMD8(0, 4, 7, 11, 14, 0, 0, 0)
        case .add9: return SIMD8(0, 4, 7, 14, 0, 0, 0, 0)
        case .sixNine: return SIMD8(0, 4, 7, 9, 14, 0, 0, 0)
        case .major7Sharp11: return SIMD8(0, 4, 7, 11, 18, 0, 0, 0)
        }
    }

    /// Number of meaningful lanes in `tones`.
    var toneCount: Int {
        switch self {
        case .minor7, .major7, .add9: return 4
        case .minor9, .major9, .sixNine, .major7Sharp11: return 5
        case .minor11: return 6
        }
    }

    /// A four-note, mostly rootless pad voicing (the bass supplies the root), in semitones above
    /// the root. Each shape is free of semitone clashes between neighboring voices.
    var padShape: SIMD4<Int32> {
        switch self {
        case .minor7: return SIMD4(3, 7, 10, 12)
        case .minor9: return SIMD4(3, 7, 10, 14)
        case .minor11: return SIMD4(3, 10, 14, 17)
        case .major7, .major9: return SIMD4(4, 7, 11, 14)
        case .add9: return SIMD4(4, 7, 12, 14)
        case .sixNine: return SIMD4(4, 9, 14, 19)
        case .major7Sharp11: return SIMD4(4, 7, 11, 18)
        }
    }
}

/// A chord name for display, such as "B♭maj7".
public struct SynthChordSymbol: Equatable, Hashable, Sendable {
    /// Pitch class of the root, 0 (C) … 11 (B).
    public var root: Int
    public var quality: SynthChordQuality

    public init(root: Int, quality: SynthChordQuality) {
        self.root = ((root % 12) + 12) % 12
        self.quality = quality
    }

    /// The chord symbol.
    public var name: String {
        let names = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return names[root] + quality.suffix
    }
}

/// The musical material of the generative sequencer, as small fixed tables.
///
/// Every chord is diatonic to the Aeolian or Dorian mode of the tonic (the shared pitch collection
/// of minor-key pop, film and ambient music), and the arpeggios only ever play chord tones, so any
/// combination the dice pick is consonant. Variety comes from the order of progressions, the
/// rhythm and contour of the arpeggio, and the bass pattern.
enum SynthHarmony {
    /// A chord within a progression: root in semitones above the tonic, and quality.
    struct Chord {
        var root: Int32
        var quality: SynthChordQuality
    }

    static var progressionCount: Int { 5 }
    static var arpeggioPatternCount: Int { 5 }
    static var rhythmCount: Int { 5 }
    static var bassPatternCount: Int { 3 }

    /// Chord `slot` (0 … 3) of progression `index`.
    static func chord(progression index: Int, slot: Int) -> Chord {
        let roots: SIMD4<Int32>
        let qualities: (SynthChordQuality, SynthChordQuality, SynthChordQuality, SynthChordQuality)
        switch index {
        case 0: // i9 – VImaj7 – IIImaj9 – VIIadd9: the "epic" Aeolian climb.
            roots = SIMD4(0, 8, 3, 10)
            qualities = (.minor9, .major7, .major9, .add9)
        case 1: // i9 – IVadd9 – i11 – VII6/9: Dorian glow.
            roots = SIMD4(0, 5, 0, 10)
            qualities = (.minor9, .add9, .minor11, .sixNine)
        case 2: // IIImaj7♯11 – VIIadd9 – v7 – i9: floating Lydian color.
            roots = SIMD4(3, 10, 7, 0)
            qualities = (.major7Sharp11, .add9, .minor7, .minor9)
        case 3: // VImaj9 – v7 – iv9 – IIImaj7: a slow descent.
            roots = SIMD4(8, 7, 5, 3)
            qualities = (.major9, .minor7, .minor9, .major7)
        default: // IIImaj9 – VII6/9 – VImaj7♯11 – i11: hymn-like.
            roots = SIMD4(3, 10, 8, 0)
            qualities = (.major9, .sixNine, .major7Sharp11, .minor11)
        }
        let s = ((slot % 4) + 4) % 4
        let quality: SynthChordQuality
        switch s {
        case 0: quality = qualities.0
        case 1: quality = qualities.1
        case 2: quality = qualities.2
        default: quality = qualities.3
        }
        return Chord(root: roots[s], quality: quality)
    }

    /// Arpeggio contour: for each of the 16 steps of a bar, an index into the ascending list of
    /// chord tones in the arpeggio register (wrapped by the list length).
    static func arpeggioPattern(_ index: Int) -> SIMD16<Int32> {
        switch index {
        case 0: return SIMD16(0, 1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1) // rise and fall
        case 1: return SIMD16(0, 2, 4, 6, 1, 3, 5, 7, 2, 4, 6, 8, 3, 5, 7, 9) // leaping
        case 2: return SIMD16(0, 5, 1, 5, 2, 5, 3, 5, 2, 5, 1, 5, 3, 5, 4, 5) // under a pedal
        case 3: return SIMD16(7, 6, 5, 4, 6, 5, 4, 3, 5, 4, 3, 2, 4, 3, 2, 1) // cascade
        default: return SIMD16(0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 8, 7, 9) // broken thirds
        }
    }

    /// Which of the 16 steps of a bar the arpeggio plays (bit n = step n).
    static func rhythm(_ index: Int) -> UInt16 {
        switch index {
        case 0: return 0x5555 // straight eighths
        case 1: return 0xFFFF // sixteenths
        case 2: return 0xDDDD // gallop: x.xx x.xx x.xx x.xx
        case 3: return 0x5249 // dotted: 3 + 3 + 3 + 3 + 2 + 2
        default: return 0x4949 // lilting: x..x ..x. x..x ..x.
        }
    }

    /// Bass pattern: up to three (start step, length in steps) hits per bar.
    static func bassPattern(_ index: Int) -> (count: Int, starts: SIMD4<Int32>, lengths: SIMD4<Int32>) {
        switch index {
        case 0: return (1, SIMD4(0, 0, 0, 0), SIMD4(15, 0, 0, 0))   // one long note
        case 1: return (2, SIMD4(0, 10, 0, 0), SIMD4(10, 5, 0, 0))  // push on the and-of-three
        default: return (3, SIMD4(0, 6, 12, 0), SIMD4(6, 5, 3, 0))  // 3 + 3 + 2
        }
    }
}
