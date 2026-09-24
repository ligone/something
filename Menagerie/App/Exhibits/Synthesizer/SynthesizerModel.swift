import AppKit
import Observation
import SynthKit

/// Everything the synthesizer exhibit shows and edits, and the bridge to the audio engine.
///
/// UI state lives here on the main actor. Every change is forwarded to the `SynthEngine`, whose
/// thread-safe API queues it for the audio thread; nothing here ever waits on audio.
@MainActor
@Observable
final class SynthesizerModel {
    // MARK: - Sound

    private var storedPatch = SynthPreset.default.patch
    /// The preset the patch was last loaded from.
    private(set) var presetID = SynthPreset.default.id

    /// The sound being played. Sliders bind straight into it.
    var patch: SynthPatch {
        get { storedPatch }
        set {
            guard newValue != storedPatch else { return }
            storedPatch = newValue
            engine?.setPatch(newValue)
        }
    }

    /// Selection for the preset picker; choosing one loads it.
    var selectedPresetID: String {
        get { presetID }
        set { selectPreset(newValue) }
    }

    var currentPreset: SynthPreset {
        SynthPreset.named(presetID) ?? SynthPreset.default
    }

    /// Whether the patch has been edited since its preset was loaded.
    var isPatchEdited: Bool {
        storedPatch != currentPreset.patch
    }

    func selectPreset(_ id: String) {
        guard let preset = SynthPreset.named(id) else { return }
        presetID = id
        patch = preset.patch
    }

    func revertToPreset() {
        patch = currentPreset.patch
    }

    // Log-scaled slider positions (0 … 1) for parameters that span several decades.

    var cutoffPosition: Double {
        get { LogScale.cutoff.position(of: storedPatch.filter.cutoff) }
        set { patch.filter.cutoff = LogScale.cutoff.value(at: newValue) }
    }

    var lfoRatePosition: Double {
        get { LogScale.lfoRate.position(of: storedPatch.lfo.rate) }
        set { patch.lfo.rate = LogScale.lfoRate.value(at: newValue) }
    }

    var delayTimePosition: Double {
        get { LogScale.delayTime.position(of: storedPatch.effects.delayTime) }
        set { patch.effects.delayTime = LogScale.delayTime.value(at: newValue) }
    }

    var reverbDecayPosition: Double {
        get { LogScale.reverbDecay.position(of: storedPatch.effects.reverbDecay) }
        set { patch.effects.reverbDecay = LogScale.reverbDecay.value(at: newValue) }
    }

    // MARK: - Output and the generative player

    private var storedVolume = 0.8

    /// Master volume, 0 … 1.
    var masterVolume: Double {
        get { storedVolume }
        set {
            storedVolume = min(max(newValue, 0), 1)
            engine?.setMasterGain(effectiveGain)
        }
    }

    private var storedTempo = 84.0

    /// Tempo of the generative player in beats per minute.
    var tempo: Double {
        get { storedTempo }
        set {
            storedTempo = min(max(newValue, SynthSequencer.tempoRange.lowerBound), SynthSequencer.tempoRange.upperBound)
            engine?.setTempo(storedTempo)
        }
    }

    /// Whether "Play me something" is on.
    private(set) var isPlayingSomething = false

    func togglePlayMeSomething() {
        setPlayingSomething(!isPlayingSomething)
    }

    func setPlayingSomething(_ playing: Bool) {
        guard playing != isPlayingSomething else { return }
        isPlayingSomething = playing
        if playing {
            // Screenshots always get the same piece; people get a new one every time.
            engine?.startSequencer(seed: AppEnvironment.isCaptureTour ? 0 : nil)
        } else {
            engine?.stopSequencer()
        }
    }

    /// While the capture tour takes screenshots the output is muted; the visualizers read the
    /// signal before the master volume, so they keep moving.
    private var effectiveGain: Double {
        AppEnvironment.isCaptureTour ? 0 : storedVolume
    }

    // MARK: - Keyboard

    /// Octave shift of the computer keyboard and the on-screen keys, −3 … +3.
    private(set) var octave = 0

    /// The note the A key plays (C4 at octave 0).
    var keyboardBaseNote: Int { 60 + 12 * octave }

    /// Notes held from this UI (mouse and computer keyboard), for instant key lighting.
    private(set) var localNotes = SynthNoteSet()

    func shiftOctave(by delta: Int) {
        octave = min(max(octave + delta, -3), 3)
    }

    // MARK: - Status

    /// Latest engine snapshot, refreshed about twelve times a second for the HUD.
    private(set) var status = SynthStatus()
    /// Output sample rate, or 0 when audio is not running.
    private(set) var sampleRate: Double = 0
    /// Set when the audio output could not be started.
    private(set) var audioProblem: String?

    // MARK: - Plumbing

    /// Per-frame data for the visualizers (not observed; read by `TimelineView`s).
    let feed = SynthVisualizerFeed()

    private let host = SynthAudioHost()
    private let keyMonitor = SynthKeyMonitor()
    @ObservationIgnored private var keyNotes: [UInt16: Int] = [:]
    @ObservationIgnored private var pointerNote: Int?
    @ObservationIgnored private var holdCounts = [Int](repeating: 0, count: 128)
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = false

    /// The audio engine, while running.
    var engine: SynthEngine? { host.synth }

    // MARK: - Lifecycle

    /// Starts audio, the status poll and the key monitor. Call when the exhibit appears.
    func activate() {
        guard !isActive else { return }
        isActive = true
        startAudio()
        keyMonitor.install { [weak self] event in
            self?.handleKey(event) ?? false
        }
        startPolling()
        if AppEnvironment.isCaptureTour {
            setPlayingSomething(true)
        }
    }

    /// Stops the player, audio, the poll and the key monitor. Call when the exhibit disappears.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        keyMonitor.remove()
        pollTask?.cancel()
        pollTask = nil
        releaseHeldNotes()
        if isPlayingSomething {
            engine?.stopSequencer()
            isPlayingSomething = false
        }
        host.stop()
        feed.attach(engine: nil)
        sampleRate = 0
        status = SynthStatus()
    }

    private func startAudio() {
        host.start(patch: storedPatch, masterGain: effectiveGain, tempo: storedTempo) { [weak self] in
            self?.restartAfterConfigurationChange()
        }
        sampleRate = host.sampleRate
        // Without an output device the synth still runs (silently) for the visualizers.
        let silent = !host.isOutputAvailable && !AppEnvironment.isCaptureTour
        audioProblem = silent ? "No audio output – showing visuals only" : nil
        feed.attach(engine: host.synth)
    }

    /// The output device changed (for example, headphones were plugged in): rebuild the graph at
    /// the new device's sample rate, carrying the current sound and player state across.
    private func restartAfterConfigurationChange() {
        guard isActive else { return }
        releaseHeldNotes()
        startAudio()
        if isPlayingSomething {
            engine?.startSequencer(seed: AppEnvironment.isCaptureTour ? 0 : nil)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard let self else { return }
                self.refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        guard let engine else { return }
        let latest = engine.status
        if latest != status { status = latest }
    }

    // MARK: - Playing notes

    /// Presses a note. Several inputs may hold the same note; it sounds until all let go.
    func playNote(_ note: Int, velocity: Double) {
        guard note >= 0, note < 128 else { return }
        holdCounts[note] += 1
        if holdCounts[note] == 1 {
            engine?.noteOn(note, velocity: velocity)
            localNotes.insert(note)
        }
    }

    /// Releases one hold of a note.
    func releaseNote(_ note: Int) {
        guard note >= 0, note < 128, holdCounts[note] > 0 else { return }
        holdCounts[note] -= 1
        if holdCounts[note] == 0 {
            engine?.noteOff(note)
            localNotes.remove(note)
        }
    }

    /// The pointer moved over the on-screen keyboard (`nil` when it is between keys or outside).
    /// Moving onto a new key releases the previous one: a glissando.
    func pointerMoved(to note: Int?, velocity: Double) {
        guard note != pointerNote else { return }
        if let previous = pointerNote { releaseNote(previous) }
        pointerNote = note
        if let note { playNote(note, velocity: velocity) }
    }

    func pointerEnded() {
        if let previous = pointerNote { releaseNote(previous) }
        pointerNote = nil
    }

    /// Lets go of everything this UI is holding, for example when the app loses focus and key-up
    /// events would never arrive.
    func releaseHeldNotes() {
        for note in keyNotes.values { releaseNote(note) }
        keyNotes.removeAll()
        pointerEnded()
        for note in 0 ..< 128 where holdCounts[note] > 0 {
            holdCounts[note] = 0
            engine?.noteOff(note)
        }
        localNotes.removeAll()
    }

    // MARK: - Computer keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown: return keyDown(event)
        case .keyUp: return keyUp(event)
        default: return false
        }
    }

    private func keyDown(_ event: NSEvent) -> Bool {
        // Never swallow shortcuts, and never steal typing from a text field.
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.isDisjoint(with: [.command, .control, .option]) { return false }
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        guard let action = SynthKeyMap.action(for: event.keyCode) else { return false }
        // Auto-repeat would retrigger the note; consume it silently (no beep either).
        if event.isARepeat { return true }

        switch action {
        case .note(let offset):
            let note = keyboardBaseNote + offset
            guard keyNotes[event.keyCode] == nil, note >= 0, note < 128 else { return true }
            keyNotes[event.keyCode] = note
            playNote(note, velocity: 0.8)
        case .octaveDown:
            shiftOctave(by: -1)
        case .octaveUp:
            shiftOctave(by: 1)
        }
        return true
    }

    private func keyUp(_ event: NSEvent) -> Bool {
        // Released even with modifiers down, so a note can never stick.
        guard let note = keyNotes.removeValue(forKey: event.keyCode) else { return false }
        releaseNote(note)
        return true
    }
}
