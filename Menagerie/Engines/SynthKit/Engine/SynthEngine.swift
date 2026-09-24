import Foundation

/// An eight-voice polyphonic subtractive synthesizer with effects and a generative sequencer.
///
/// ## Threads
///
/// The engine is driven from two sides:
///
/// - **Control** (typically the main thread): `noteOn`, `noteOff`, `setPatch`, the sequencer
///   controls, `status` and the visualizer taps. These are thread-safe and may briefly wait for
///   the audio thread's (tiny) critical sections.
/// - **Audio** (the real-time render thread): `render(frameCount:left:right:)` only. It never
///   allocates, never blocks and never waits: it *tries* the lock once at the start of a buffer to
///   collect queued commands and the latest patch, and once at the end to publish its status.
///   If the lock is busy it carries on and catches up on the next buffer. See `SynthTryLock` for
///   why this is a try-lock rather than an atomics-free ring.
///
/// Events queue in order and apply at the start of the next buffer. The patch and master volume
/// are "latest value wins", and continuous parameters glide to new values, so dragging a slider
/// never clicks. Sequencer events are scheduled sample-accurately inside the render loop.
///
/// ## Signal flow
///
/// 8 × (2 oscillators + sub → drive → TPT state-variable filter → amp envelope → pan)
/// → DC blocker → chorus → ping-pong delay → FDN reverb → soft clipper → [visualizer tap]
/// → master volume.
public final class SynthEngine: @unchecked Sendable {
    /// Number of voices.
    public static let polyphony = SynthRenderer.voiceCount

    /// Output sample rate in hertz.
    public let sampleRate: Double

    private let renderer: SynthRenderer
    private let lock = SynthTryLock()
    private let shared: UnsafeMutablePointer<SharedState>
    private let commands: UnsafeMutablePointer<SynthCommand>
    private let drained: UnsafeMutablePointer<SynthCommand>
    private static let commandCapacity = 512

    // Audio-thread state.
    private var loadAverage: Double = 0
    private var workingStatus = SynthStatus()

    /// Creates an engine rendering at `sampleRate`.
    public init(sampleRate: Double, patch: SynthPatch = SynthPreset.default.patch, masterGain: Double = 0.8) {
        let rate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        self.sampleRate = rate
        let gain = Float(SynthMath.sanitize(masterGain, 0 ... 1.5, fallback: 0.8))
        renderer = SynthRenderer(sampleRate: rate, patch: patch, masterGain: gain)
        shared = .allocate(capacity: 1)
        shared.initialize(to: SharedState(patch: patch.sanitized(), masterGain: gain, tempo: renderer.sequencer.tempo))
        commands = .allocate(capacity: Self.commandCapacity)
        drained = .allocate(capacity: Self.commandCapacity)
        commands.initialize(repeating: SynthCommand(kind: .releaseAll), count: Self.commandCapacity)
        drained.initialize(repeating: SynthCommand(kind: .releaseAll), count: Self.commandCapacity)
    }

    deinit {
        shared.deinitialize(count: 1)
        shared.deallocate()
        commands.deallocate()
        drained.deallocate()
    }

    // MARK: - Control

    /// Starts `note` (MIDI 0 … 127) with a velocity in 0 … 1.
    public func noteOn(_ note: Int, velocity: Double = 0.8) {
        guard note >= 0, note < 128 else { return }
        enqueue(SynthCommand(kind: .noteOn, note: Int32(note), velocity: Float(SynthMath.sanitize(velocity, 0 ... 1, fallback: 0.8))))
    }

    /// Releases `note`.
    public func noteOff(_ note: Int) {
        guard note >= 0, note < 128 else { return }
        enqueue(SynthCommand(kind: .noteOff, note: Int32(note)))
    }

    /// Releases every note the player is holding. The sequencer keeps playing.
    public func releaseAllNotes() {
        enqueue(SynthCommand(kind: .releaseAll))
    }

    /// Replaces the patch. Continuous parameters glide to their new values.
    public func setPatch(_ patch: SynthPatch) {
        let clean = patch.sanitized()
        lock.lock()
        shared.pointee.patch = clean
        shared.pointee.patchIsNew = true
        lock.unlock()
    }

    /// Sets the master volume, 0 … 1.5. It is applied after the visualizer tap, so 0 mutes the
    /// output while the oscilloscope and spectrum keep moving.
    public func setMasterGain(_ gain: Double) {
        let clean = Float(SynthMath.sanitize(gain, 0 ... 1.5, fallback: 0))
        lock.lock()
        shared.pointee.masterGain = clean
        shared.pointee.masterGainIsNew = true
        lock.unlock()
    }

    /// Starts the generative sequencer. Without a seed, every start plays a new piece.
    public func startSequencer(seed: UInt64? = nil) {
        enqueue(SynthCommand(kind: .startSequencer, seed: seed ?? 0, hasSeed: seed != nil))
    }

    /// Stops the sequencer and releases its notes.
    public func stopSequencer() {
        enqueue(SynthCommand(kind: .stopSequencer))
    }

    /// Sets the sequencer tempo in beats per minute (see `SynthSequencer.tempoRange`).
    public func setTempo(_ bpm: Double) {
        let clean = SynthMath.sanitize(bpm, SynthSequencer.tempoRange, fallback: 84)
        lock.lock()
        shared.pointee.tempo = clean
        shared.pointee.tempoIsNew = true
        lock.unlock()
    }

    /// Silences everything immediately, including effect tails, and stops the sequencer.
    public func reset() {
        enqueue(SynthCommand(kind: .reset))
    }

    // MARK: - Observation

    /// The most recent snapshot published by the audio thread.
    public var status: SynthStatus {
        lock.lock()
        defer { lock.unlock() }
        return shared.pointee.status
    }

    /// Copies the newest output samples (mono, before the master volume) into `destination`,
    /// oldest first. Positions before the start of the stream are zero.
    ///
    /// - Returns: The number of samples written (at most 32 768).
    @discardableResult
    public func copyRecentOutput(into destination: UnsafeMutableBufferPointer<Float>) -> Int {
        guard let base = destination.baseAddress, destination.count > 0 else { return 0 }
        lock.lock()
        let end = shared.pointee.monitorEnd
        lock.unlock()
        // The audio thread only ever writes past `end`, and the ring is twice as long as the
        // longest read, so these samples cannot change while they are copied.
        let count = min(destination.count, SynthRenderer.monitorCapacity / 2)
        let mask = SynthRenderer.monitorCapacity - 1
        let monitor = renderer.monitor
        for k in 0 ..< count {
            let index = end - count + k
            base[k] = index < 0 ? 0 : monitor[index & mask]
        }
        return count
    }

    /// Copies the newest output samples into an array (see `copyRecentOutput(into:)` for buffers).
    @discardableResult
    public func copyRecentOutput(into destination: inout [Float]) -> Int {
        destination.withUnsafeMutableBufferPointer { copyRecentOutput(into: $0) }
    }

    /// Fills `output` with a stable oscilloscope trace of the recent output, starting at a rising
    /// zero crossing (see `SynthOscilloscope`).
    ///
    /// - Returns: `true` if a trigger point was found.
    @discardableResult
    public func fillOscilloscope(_ output: inout [Float]) -> Bool {
        let count = output.count
        guard count > 0 else { return false }
        let historyLength = min(count * 3, SynthRenderer.monitorCapacity / 2)
        return withUnsafeTemporaryAllocation(of: Float.self, capacity: historyLength) { history in
            copyRecentOutput(into: history)
            return output.withUnsafeMutableBufferPointer { out in
                SynthOscilloscope.trigger(history: UnsafeBufferPointer(history), into: out)
            }
        }
    }

    // MARK: - Audio

    /// Renders `frameCount` frames into two non-interleaved channel buffers.
    ///
    /// Call only from the audio thread (one thread at a time). Real-time safe: no allocation,
    /// no blocking, no Objective-C, no Swift concurrency.
    public func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        guard frameCount > 0 else { return }
        let started = DispatchTime.now().uptimeNanoseconds

        var commandCount = 0
        var newPatch: SynthPatch?
        var newGain: Float?
        var newTempo: Double?
        if lock.tryLock() {
            let s = shared
            commandCount = s.pointee.commandCount
            if commandCount > 0 {
                drained.update(from: commands, count: commandCount)
                s.pointee.commandCount = 0
            }
            if s.pointee.patchIsNew {
                newPatch = s.pointee.patch
                s.pointee.patchIsNew = false
            }
            if s.pointee.masterGainIsNew {
                newGain = s.pointee.masterGain
                s.pointee.masterGainIsNew = false
            }
            if s.pointee.tempoIsNew {
                newTempo = s.pointee.tempo
                s.pointee.tempoIsNew = false
            }
            lock.unlock()
        }
        if let newPatch { renderer.applyPatch(newPatch) }
        if let newGain { renderer.setMasterGain(newGain) }
        if let newTempo { renderer.sequencer.setTempo(newTempo) }
        for i in 0 ..< commandCount { apply(drained[i]) }

        renderer.render(frameCount: frameCount, left: left, right: right)

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- started)
        let budget = Double(frameCount) / sampleRate * 1e9
        loadAverage += (elapsed / budget - loadAverage) * 0.05
        renderer.fillStatus(&workingStatus)
        workingStatus.cpuLoad = loadAverage
        if lock.tryLock() {
            shared.pointee.status = workingStatus
            shared.pointee.monitorEnd = renderer.monitorWritten
            lock.unlock()
        }
    }

    // MARK: - Private

    private func enqueue(_ command: SynthCommand) {
        lock.lock()
        if shared.pointee.commandCount >= Self.commandCapacity {
            // Nothing is draining the queue (audio stopped). Collapse the backlog into a release
            // so that no note can be left stuck on when audio resumes.
            commands[0] = SynthCommand(kind: .releaseAll)
            shared.pointee.commandCount = 1
        }
        commands[shared.pointee.commandCount] = command
        shared.pointee.commandCount += 1
        lock.unlock()
    }

    private func apply(_ command: SynthCommand) {
        switch command.kind {
        case .noteOn: renderer.noteOn(note: Int(command.note), velocity: command.velocity, source: .player)
        case .noteOff: renderer.noteOff(note: Int(command.note), source: .player)
        case .releaseAll: renderer.releasePlayerNotes()
        case .startSequencer: renderer.startSequencer(seed: command.hasSeed ? command.seed : nil)
        case .stopSequencer: renderer.stopSequencer()
        case .reset: renderer.reset()
        }
    }
}

/// A queued control command. Plain data, so queuing it never retains or releases anything.
struct SynthCommand {
    enum Kind: UInt8 {
        case noteOn, noteOff, releaseAll, startSequencer, stopSequencer, reset
    }

    var kind: Kind
    var note: Int32 = 0
    var velocity: Float = 0
    var seed: UInt64 = 0
    var hasSeed = false
}

/// State shared between the control and audio threads, guarded by `SynthEngine.lock`.
struct SharedState {
    var patch: SynthPatch
    var patchIsNew = false
    var masterGain: Float
    var masterGainIsNew = false
    var tempo: Double
    var tempoIsNew = false
    var commandCount = 0
    var status = SynthStatus()
    var monitorEnd = 0

    init(patch: SynthPatch, masterGain: Float, tempo: Double) {
        self.patch = patch
        self.masterGain = masterGain
        self.tempo = tempo
    }
}
