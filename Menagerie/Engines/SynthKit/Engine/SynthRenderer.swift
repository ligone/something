import Foundation

/// The audio-thread half of the engine: voices and their allocation, the sequencer, the effects
/// chain and the master section. It is single-threaded; `SynthEngine` hands it commands between
/// blocks. Everything is allocated in `init`, so rendering never touches the allocator.
final class SynthRenderer {
    static let voiceCount = 8
    static let controlInterval = SynthVoice.maxChunk
    static let maxBlock = 256
    /// Capacity of the visualizer ring (a power of two, ~1.4 s at 48 kHz).
    static let monitorCapacity = 1 << 16

    let sampleRate: Double
    let sequencer: SynthSequencer
    /// Ring buffer of the mono mix after the soft clipper but before the master volume, so the
    /// visualizers keep working when the output is muted.
    let monitor: UnsafeMutablePointer<Float>
    /// Total samples ever written to `monitor`; the newest sample is at `(monitorWritten − 1) & mask`.
    private(set) var monitorWritten = 0
    /// Absolute sample time of the next sample to render.
    private(set) var sampleClock: Int64 = 0
    private(set) var patch: SynthPatch

    private let voices: UnsafeMutablePointer<SynthVoice>
    /// Stereo position of each voice at full spread: alternating sides, spreading outwards.
    private let panPositions = SIMD8<Float>(-0.35, 0.35, -0.7, 0.7, -0.15, 0.15, -0.95, 0.95)
    private let mixLeft: UnsafeMutablePointer<Float>
    private let mixRight: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private let chorus: StereoChorus
    private let delay: PingPongDelay
    private let reverb: FDNReverb
    private var dcLeft: DCBlocker
    private var dcRight: DCBlocker
    private let stealFadeSamples: Int
    private let tickSmoothing: Float
    private let gainSmoothing: Float
    private let voiceHeadroom: Float = 0.28

    private var parameters = VoiceParameters()
    private var lfo = SynthLFO()
    private var nextAge: UInt64 = 1
    private var controlCountdown = 0
    private var silentSamples = 0
    /// Starts asleep: until the first note or sequencer start there is nothing to compute.
    private var isAsleep = true
    private var sequencerRuns: UInt64 = 0
    private var lastPeak: Float = 0

    private var cutoff = Smoothed()
    private var resonance = Smoothed()
    private var osc1Gain = Smoothed()
    private var osc2Gain = Smoothed()
    private var subGain = Smoothed()
    private var drive = Smoothed()
    private var outputGain = Smoothed()
    private var masterGain: Float
    private var masterGainTarget: Float

    init(sampleRate: Double, patch: SynthPatch, masterGain: Float) {
        self.sampleRate = sampleRate
        sequencer = SynthSequencer(sampleRate: sampleRate)
        monitor = .allocate(capacity: Self.monitorCapacity)
        monitor.initialize(repeating: 0, count: Self.monitorCapacity)
        voices = .allocate(capacity: Self.voiceCount)
        for i in 0 ..< Self.voiceCount {
            let seed = UInt32(truncatingIfNeeded: (i + 1) &* 0x9E37_79B9)
            (voices + i).initialize(to: SynthVoice(seed: seed, sampleRate: sampleRate))
        }
        mixLeft = .allocate(capacity: Self.maxBlock)
        mixRight = .allocate(capacity: Self.maxBlock)
        scratch = .allocate(capacity: 3 * SynthVoice.maxChunk)
        mixLeft.initialize(repeating: 0, count: Self.maxBlock)
        mixRight.initialize(repeating: 0, count: Self.maxBlock)
        scratch.initialize(repeating: 0, count: 3 * SynthVoice.maxChunk)
        chorus = StereoChorus(sampleRate: sampleRate)
        delay = PingPongDelay(sampleRate: sampleRate)
        reverb = FDNReverb(sampleRate: sampleRate)
        dcLeft = DCBlocker(sampleRate: sampleRate)
        dcRight = DCBlocker(sampleRate: sampleRate)
        stealFadeSamples = max(Int(0.003 * sampleRate), 16)
        tickSmoothing = SynthMath.smoothingCoefficient(time: 0.012, rate: sampleRate / Double(Self.controlInterval))
        gainSmoothing = SynthMath.smoothingCoefficient(time: 0.02, rate: sampleRate)
        self.masterGain = masterGain
        masterGainTarget = masterGain
        parameters.sampleRate = Float(sampleRate)
        parameters.controlInterval = Float(Self.controlInterval)
        self.patch = patch.sanitized()
        applyPatch(self.patch, immediately: true)
    }

    deinit {
        voices.deinitialize(count: Self.voiceCount)
        voices.deallocate()
        monitor.deallocate()
        mixLeft.deallocate()
        mixRight.deallocate()
        scratch.deallocate()
    }

    // MARK: - Control

    /// Takes a new patch. Continuous parameters glide to their new values over ~12 ms.
    func applyPatch(_ newPatch: SynthPatch, immediately: Bool = false) {
        let p = newPatch.sanitized()
        patch = p
        for i in 0 ..< Self.voiceCount {
            voices[i].configure(p, sampleRate: sampleRate)
        }
        lfo.shape = p.lfo.shape
        parameters.osc1Semitones = Float(p.osc1.octave * 12) + Float(p.osc1.detune) / 100
        parameters.osc2Semitones = Float(p.osc2.octave * 12) + Float(p.osc2.detune) / 100
        parameters.envelopeAmount = Float(p.filter.envelopeAmount)
        parameters.keyTracking = Float(p.filter.keyTracking)
        parameters.velocityAmount = Float(p.filter.velocityAmount)
        parameters.mode = p.filter.mode

        cutoff.target = log2(Float(p.filter.cutoff))
        resonance.target = Float(p.filter.resonance)
        osc1Gain.target = Float(1 - p.oscMix)
        osc2Gain.target = Float(p.oscMix)
        subGain.target = Float(p.subLevel)
        let d = Float(p.filter.drive)
        drive.target = 0.5 + 3.5 * d * d
        outputGain.target = Float(p.level) * voiceHeadroom
        if immediately {
            cutoff.value = cutoff.target
            resonance.value = resonance.target
            osc1Gain.value = osc1Gain.target
            osc2Gain.value = osc2Gain.target
            subGain.value = subGain.target
            drive.value = drive.target
            outputGain.value = outputGain.target
            updateVoiceParameters()
        }
    }

    /// Sets the master volume (applied after the soft clipper, with a 20 ms glide).
    func setMasterGain(_ gain: Float) {
        masterGainTarget = min(max(gain.isFinite ? gain : 0, 0), 1.5)
    }

    /// Starts a note from the given source.
    func noteOn(note: Int, velocity: Float, source: SynthNoteSource) {
        guard note >= 0, note < 128 else { return }
        let v = min(max(velocity.isFinite ? velocity : 0.8, 0.01), 1)
        let sensitivity = Float(patch.velocitySensitivity)
        wake()

        // Same note from the same source: strike it again on its own voice.
        for i in 0 ..< Self.voiceCount {
            let state = voices[i].state
            if (state == .held || state == .released) && voices[i].note == note && voices[i].source == source {
                voices[i].retrigger(velocity: v, age: takeAge(), sensitivity: sensitivity)
                return
            }
            if state == .stealing && voices[i].pendingNote == note && voices[i].pendingSource == source {
                voices[i].beginSteal(note: note, velocity: v, source: source, fadeSamples: stealFadeSamples)
                return
            }
        }
        // A free voice.
        for i in 0 ..< Self.voiceCount where voices[i].state == .idle {
            startVoice(i, note: note, velocity: v, source: source)
            return
        }
        // Steal the oldest voice, preferring release tails over held keys, with a 3 ms fade.
        var victim = oldestVoice(in: .released)
        if victim < 0 { victim = oldestVoice(in: .held) }
        if victim < 0 { victim = oldestVoice(in: .stealing) }
        if victim >= 0 {
            voices[victim].beginSteal(note: note, velocity: v, source: source, fadeSamples: stealFadeSamples)
        }
    }

    /// Releases a note from the given source.
    func noteOff(note: Int, source: SynthNoteSource) {
        for i in 0 ..< Self.voiceCount {
            if voices[i].state == .held && voices[i].note == note && voices[i].source == source {
                voices[i].release()
            } else if voices[i].state == .stealing && voices[i].pendingNote == note && voices[i].pendingSource == source {
                voices[i].pendingReleased = true
            }
        }
    }

    /// Releases every note the player is holding (the sequencer keeps playing).
    func releasePlayerNotes() {
        for i in 0 ..< Self.voiceCount {
            if voices[i].state == .held && voices[i].source == .player {
                voices[i].release()
            } else if voices[i].state == .stealing && voices[i].pendingSource == .player {
                voices[i].pendingReleased = true
            }
        }
    }

    /// Starts the generative sequencer; without a seed, each run plays a new piece.
    func startSequencer(seed: UInt64?) {
        let chosen = seed ?? sequencerRuns
        sequencerRuns = chosen &+ 1
        if sequencer.isPlaying { stopSequencer() }
        sequencer.start(at: sampleClock, seed: chosen)
        wake()
    }

    /// Stops the sequencer and releases its notes.
    func stopSequencer() {
        sequencer.stop(at: sampleClock) { event in handle(event) }
    }

    /// Silences everything at once: voices, effect tails and the sequencer.
    func reset() {
        for i in 0 ..< Self.voiceCount { voices[i].kill() }
        if sequencer.isPlaying { sequencer.stop(at: sampleClock) { _ in } }
        chorus.reset()
        delay.reset()
        reverb.reset()
        dcLeft.reset()
        dcRight.reset()
    }

    /// Copies the current voice and sequencer state into `status`.
    func fillStatus(_ status: inout SynthStatus) {
        var active = 0
        var held = SynthNoteSet()
        var sounding = SynthNoteSet()
        for i in 0 ..< Self.voiceCount where voices[i].state != .idle {
            active += 1
            let note = voices[i].effectiveNote
            sounding.insert(note)
            if voices[i].isGated { held.insert(note) }
        }
        status.activeVoices = active
        status.heldNotes = held
        status.soundingNotes = sounding
        status.peakLevel = lastPeak
        status.isSequencerPlaying = sequencer.isPlaying
        status.chord = sequencer.currentChord
        status.sequencerStep = sequencer.stepIndex
    }

    // MARK: - Rendering

    /// Renders `frameCount` samples of stereo output (any length; processed in blocks of 256).
    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        var offset = 0
        while offset < frameCount {
            let n = min(frameCount - offset, Self.maxBlock)
            renderBlock(n, left: left + offset, right: right + offset)
            offset += n
        }
    }

    private func renderBlock(_ n: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if isAsleep {
            // Nothing is playing and every tail has died away: skip the DSP entirely.
            left.update(repeating: 0, count: n)
            right.update(repeating: 0, count: n)
            writeMonitorSilence(n)
            sampleClock += Int64(n)
            lastPeak = 0
            return
        }

        mixLeft.update(repeating: 0, count: n)
        mixRight.update(repeating: 0, count: n)
        var position = 0
        while position < n {
            // Sequencer events land exactly on their sample: chunks end where the next one is due.
            if sequencer.isPlaying {
                sequencer.emitEvents(through: sampleClock) { event in handle(event) }
            }
            if controlCountdown <= 0 {
                controlTick()
                controlCountdown = Self.controlInterval
            }
            var chunk = min(n - position, controlCountdown)
            if sequencer.isPlaying {
                let untilEvent = sequencer.nextEventTime - sampleClock
                if untilEvent > 0 && untilEvent < Int64(chunk) { chunk = Int(untilEvent) }
            }
            renderVoices(left: mixLeft + position, right: mixRight + position, count: chunk)
            position += chunk
            sampleClock += Int64(chunk)
            controlCountdown -= chunk
        }

        var dcL = dcLeft
        var dcR = dcRight
        for i in 0 ..< n {
            mixLeft[i] = dcL.process(mixLeft[i])
            mixRight[i] = dcR.process(mixRight[i])
        }
        dcLeft = dcL
        dcRight = dcR

        let fx = patch.effects
        // While the generative player runs, echoes lock to its tempo (the delay glides there).
        let echoTime = sequencer.isPlaying ? SynthSequencer.syncedDelayTime(fx.delayTime, tempo: sequencer.tempo) : fx.delayTime
        chorus.process(left: mixLeft, right: mixRight, count: n, mix: Float(fx.chorusMix))
        delay.process(left: mixLeft, right: mixRight, count: n, time: Float(echoTime), feedback: Float(fx.delayFeedback), mix: Float(fx.delayMix))
        reverb.process(left: mixLeft, right: mixRight, count: n, decay: Float(fx.reverbDecay), damping: Float(fx.reverbDamping), mix: Float(fx.reverbMix))

        // Master: soft clip, tap for the visualizers, then the volume.
        let mask = Self.monitorCapacity - 1
        let monitor = self.monitor
        var writeIndex = monitorWritten
        var gain = masterGain
        let gainTarget = masterGainTarget
        let smoothing = gainSmoothing
        var peak: Float = 0
        var checksum: Float = 0
        for i in 0 ..< n {
            let l = SoftClipper.process(mixLeft[i])
            let r = SoftClipper.process(mixRight[i])
            monitor[writeIndex & mask] = (l + r) * 0.5
            writeIndex += 1
            gain += (gainTarget - gain) * smoothing
            left[i] = l * gain
            right[i] = r * gain
            peak = max(peak, max(abs(l), abs(r)))
            checksum += l + r
        }
        monitorWritten = writeIndex
        // Snap when close so a muted output (target 0) cannot decay into denormals.
        masterGain = abs(gainTarget - gain) < 1e-6 ? gainTarget : gain
        lastPeak = peak

        if !checksum.isFinite {
            // Defensive: should never happen, but a NaN must not live on in the effect loops.
            reset()
            left.update(repeating: 0, count: n)
            right.update(repeating: 0, count: n)
            lastPeak = 0
        }
        updateSleep(peak: peak, count: n)
    }

    private func renderVoices(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0 ..< Self.voiceCount where voices[i].state != .idle {
            voices[i].render(left: left, right: right, count: count, parameters: parameters, scratch: scratch)
            if voices[i].isReadyToStartPendingNote {
                let note = voices[i].pendingNote
                let velocity = voices[i].pendingVelocity
                let source = voices[i].pendingSource
                let released = voices[i].pendingReleased
                startVoice(i, note: note, velocity: velocity, source: source)
                if released { voices[i].release() }
            }
        }
    }

    private func controlTick() {
        let c = tickSmoothing
        cutoff.step(c)
        resonance.step(c)
        osc1Gain.step(c)
        osc2Gain.step(c)
        subGain.step(c)
        drive.step(c)
        outputGain.step(c)
        lfo.advance(seconds: Double(Self.controlInterval) / sampleRate, rate: patch.lfo.rate)
        updateVoiceParameters()
        for i in 0 ..< Self.voiceCount where voices[i].state != .idle {
            voices[i].updateControl(parameters, immediate: false)
        }
    }

    private func updateVoiceParameters() {
        let modulation = lfo.value
        parameters.vibratoSemitones = modulation * Float(patch.lfo.pitchDepth) / 100
        parameters.lfoCutoffOctaves = modulation * Float(patch.lfo.cutoffDepth)
        parameters.cutoffOctaves = cutoff.value
        parameters.damping = SVFilter.damping(resonance: resonance.value)
        parameters.osc1Gain = osc1Gain.value
        parameters.osc2Gain = osc2Gain.value
        parameters.subGain = subGain.value
        parameters.drive = drive.value
        // Unity gain for a full-scale input, whatever the drive.
        parameters.driveMakeup = 1 / SynthMath.softSaturate(drive.value)
        parameters.outputGain = outputGain.value
    }

    // MARK: - Helpers

    private func handle(_ event: SynthSequencer.Event) {
        switch event.kind {
        case .noteOn: noteOn(note: event.note, velocity: event.velocity, source: .sequencer)
        case .noteOff: noteOff(note: event.note, source: .sequencer)
        }
    }

    private func startVoice(_ index: Int, note: Int, velocity: Float, source: SynthNoteSource) {
        let pan = panPositions[index] * Float(patch.stereoSpread)
        voices[index].start(note: note, velocity: velocity, source: source, age: takeAge(), sensitivity: Float(patch.velocitySensitivity), pan: pan, parameters: parameters)
    }

    private func oldestVoice(in state: SynthVoice.State) -> Int {
        var oldest = -1
        for i in 0 ..< Self.voiceCount where voices[i].state == state {
            if oldest < 0 || voices[i].age < voices[oldest].age { oldest = i }
        }
        return oldest
    }

    private func takeAge() -> UInt64 {
        defer { nextAge &+= 1 }
        return nextAge
    }

    private var hasActiveVoices: Bool {
        for i in 0 ..< Self.voiceCount where voices[i].state != .idle { return true }
        return false
    }

    private func wake() {
        isAsleep = false
        silentSamples = 0
    }

    /// Goes to sleep after a second of silence with no voices and no sequencer.
    private func updateSleep(peak: Float, count: Int) {
        if peak < 1e-6 && !sequencer.isPlaying && !hasActiveVoices {
            silentSamples += count
            if Double(silentSamples) > sampleRate { isAsleep = true }
        } else {
            silentSamples = 0
        }
    }

    private func writeMonitorSilence(_ n: Int) {
        let mask = Self.monitorCapacity - 1
        for i in 0 ..< n { monitor[(monitorWritten + i) & mask] = 0 }
        monitorWritten += n
    }
}

/// A one-pole smoothed parameter, advanced at control rate.
struct Smoothed {
    var value: Float = 0
    var target: Float = 0

    /// Moves toward the target, snapping once close so a target of zero cannot decay into
    /// denormals (which are extremely slow on x86).
    @inline(__always)
    mutating func step(_ coefficient: Float) {
        let difference = target - value
        value = abs(difference) < 1e-6 ? target : value + difference * coefficient
    }
}
