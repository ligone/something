/// A snapshot of what the engine is doing, published by the audio thread once per render call.
///
/// It is a plain value (no references), so it crosses threads with a simple copy.
public struct SynthStatus: Equatable, Sendable {
    /// Voices currently producing sound (including release tails), 0 … `SynthEngine.polyphony`.
    public var activeVoices = 0
    /// Notes whose key is down, from any source (player or sequencer).
    public var heldNotes = SynthNoteSet()
    /// Notes still audible, including release tails.
    public var soundingNotes = SynthNoteSet()
    /// Render time divided by the duration of the audio rendered, smoothed; 1 means 100 % of the
    /// real-time budget.
    public var cpuLoad: Double = 0
    /// Peak level of the last block before the master volume, 0 … 1.
    public var peakLevel: Float = 0
    /// Whether the generative sequencer is playing.
    public var isSequencerPlaying = false
    /// The chord the sequencer is playing, if any.
    public var chord: SynthChordSymbol?
    /// Sixteenth-note step of the sequencer since it started.
    public var sequencerStep = 0

    public init() {}
}
