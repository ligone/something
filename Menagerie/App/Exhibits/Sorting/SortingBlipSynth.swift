import AVFoundation
import QuartzCore
import os

/// One short tone: a sine–triangle blend with a 2 ms attack and an
/// exponential decay.
struct SortingBlip {
    var frequency: Float
    /// Peak level before the limiter, roughly 0…0.4.
    var amplitude: Float
    /// Stereo position from −1 (left) to 1 (right).
    var pan: Float
    /// Seconds for the tone to fade by 40 dB.
    var decay: Float
    /// 0 for a pure sine, 1 for a triangle, which is brighter.
    var brightness: Float
    /// Seconds to wait, from the start of the next audio buffer, before
    /// sounding. Spreading a frame's blips across the frame keeps fast sorts
    /// from pulsing at the display's refresh rate.
    var delay: Float
}

/// A small polyphonic synthesizer for sonifying array accesses.
///
/// Main-thread API: `play(_:)`, `volume`, `stop()`. The engine starts
/// lazily on the first blip, so an exhibit that never makes a sound never
/// touches the audio hardware. It never uses `inputNode`, which would ask for
/// microphone access.
final class SortingBlipSynth {
    private let mailbox = SortingBlipMailbox(capacity: 512)
    private var engine: AVAudioEngine?
    private var lastFailedStart: CFTimeInterval = -.infinity

    /// Output level, 0…1.
    var volume: Float = 0.7 {
        didSet { engine?.mainMixerNode.outputVolume = volume }
    }

    deinit {
        engine?.stop()
    }

    /// Queues blips for the audio thread, starting the engine if needed.
    func play(_ blips: [SortingBlip]) {
        guard !blips.isEmpty, startIfNeeded() else { return }
        mailbox.post(blips)
    }

    /// Stops the engine and forgets any blips still waiting.
    func stop() {
        engine?.stop()
        mailbox.removeAll()
    }

    /// Returns whether the engine is running, starting it if necessary.
    /// After a failed start (no output device, say) it waits a second before
    /// trying again. After an output device change the engine stops by
    /// itself, and the next blip restarts it.
    private func startIfNeeded() -> Bool {
        if let engine, engine.isRunning { return true }
        let now = CACurrentMediaTime()
        guard now - lastFailedStart > 1 else { return false }

        guard let engine = engine ?? makeEngine() else {
            lastFailedStart = now
            return false
        }
        do {
            try engine.start()
            return true
        } catch {
            lastFailedStart = now
            return false
        }
    }

    private func makeEngine() -> AVAudioEngine? {
        let engine = AVAudioEngine()
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            return nil
        }
        let renderer = SortingBlipRenderer(sampleRate: Float(sampleRate), mailbox: mailbox)
        let source = Self.makeSourceNode(format: format, renderer: renderer)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        self.engine = engine
        return engine
    }

    /// Builds the source node. This is a static, nonisolated function on
    /// purpose: the render block runs on the real-time audio thread, so it
    /// must not inherit any actor isolation from the code that creates it.
    private static func makeSourceNode(format: AVAudioFormat, renderer: SortingBlipRenderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count > 0, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            let sounding = renderer.render(frameCount: Int(frameCount), left: left, right: right)
            if !sounding {
                isSilence.pointee = true
            }
            return noErr
        }
    }
}

/// Carries blips from the main thread to the audio render thread.
///
/// The main thread takes an `os_unfair_lock` to post. The render thread only
/// ever *tries* the lock: if the main thread happens to hold it, the blips
/// simply wait for the next buffer a few milliseconds later. So the audio
/// thread never blocks, and with fixed storage it never allocates either.
final class SortingBlipMailbox: @unchecked Sendable {
    let capacity: Int
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let slots: UnsafeMutablePointer<SortingBlip>
    private let count: UnsafeMutablePointer<Int>

    init(capacity: Int) {
        self.capacity = capacity
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        slots = .allocate(capacity: capacity)
        count = .allocate(capacity: 1)
        count.initialize(to: 0)
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
        slots.deallocate()
        count.deinitialize(count: 1)
        count.deallocate()
    }

    /// Main thread. Blips beyond the free capacity are dropped: if the audio
    /// thread has fallen that far behind, they'd be too late to matter.
    func post(_ blips: [SortingBlip]) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        let accepted = min(capacity - count.pointee, blips.count)
        for index in 0..<max(0, accepted) {
            (slots + count.pointee + index).initialize(to: blips[index])
        }
        count.pointee += max(0, accepted)
    }

    /// Main thread. Discards any blips that haven't been collected.
    func removeAll() {
        os_unfair_lock_lock(lock)
        count.pointee = 0
        os_unfair_lock_unlock(lock)
    }

    /// Render thread. Hands each waiting blip to `body` and empties the
    /// mailbox, or does nothing at all if the lock is busy.
    func drain(_ body: (SortingBlip) -> Void) {
        guard os_unfair_lock_trylock(lock) else { return }
        for index in 0..<count.pointee {
            body(slots[index])
        }
        count.pointee = 0
        os_unfair_lock_unlock(lock)
    }
}

/// The audio-thread half of the synth: sixteen voices and a limiter. Once
/// the source node starts, only the render thread touches this object, and
/// all of its mutable state lives in manually allocated memory, so rendering
/// involves no locks, allocations or exclusivity checks.
final class SortingBlipRenderer: @unchecked Sendable {
    private struct Voice {
        var isActive = false
        var phase: Float = 0
        var increment: Float = 0
        var level: Float = 0
        var peak: Float = 0
        var attackStep: Float = 0
        var attackRemaining = 0
        var decayFactor: Float = 1
        var delay = 0
        var gainLeft: Float = 0
        var gainRight: Float = 0
        var brightness: Float = 0
    }

    static let voiceCount = 16

    private let sampleRate: Float
    private let mailbox: SortingBlipMailbox
    private let voices: UnsafeMutablePointer<Voice>
    /// The limiter's envelope follower.
    private let envelope: UnsafeMutablePointer<Float>
    private let attackSamples: Int
    private let releaseFactor: Float
    /// Level above which the limiter starts turning the mix down.
    private let threshold: Float = 0.5

    init(sampleRate: Float, mailbox: SortingBlipMailbox) {
        self.sampleRate = sampleRate
        self.mailbox = mailbox
        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        envelope = .allocate(capacity: 1)
        envelope.initialize(to: 0)
        attackSamples = max(1, Int(0.002 * sampleRate))
        releaseFactor = exp(-1 / (0.15 * sampleRate))
    }

    deinit {
        voices.deinitialize(count: Self.voiceCount)
        voices.deallocate()
        envelope.deinitialize(count: 1)
        envelope.deallocate()
    }

    /// Renders one buffer. `right` is nil for a mono output. Returns false
    /// when the buffer is pure silence.
    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) -> Bool {
        mailbox.drain { start($0) }

        left.update(repeating: 0, count: frameCount)
        right?.update(repeating: 0, count: frameCount)
        let mono = right == nil
        let rightOut = right ?? left

        var sounding = false
        for index in 0..<Self.voiceCount where voices[index].isActive {
            sounding = true
            renderVoice(&voices[index], frameCount: frameCount, left: left, right: rightOut, mono: mono)
        }
        guard sounding else {
            // Nothing playing: the buffer is silent. Let the limiter keep
            // releasing through the silence, as it would sample by sample.
            envelope.pointee *= pow(releaseFactor, Float(frameCount))
            return false
        }
        limit(frameCount: frameCount, left: left, right: right)
        return true
    }

    /// Assigns a blip to a free voice, or steals the quietest one. Voices
    /// still waiting out their delay count at their peak level, so a burst of
    /// new blips doesn't cancel itself.
    private func start(_ blip: SortingBlip) {
        var chosen = 0
        var quietest = Float.greatestFiniteMagnitude
        for index in 0..<Self.voiceCount {
            let voice = voices[index]
            if !voice.isActive {
                chosen = index
                break
            }
            let loudness = voice.delay > 0 || voice.attackRemaining > 0 ? voice.peak : voice.level
            if loudness < quietest {
                quietest = loudness
                chosen = index
            }
        }

        // Equal-power panning.
        let angle = (min(max(blip.pan, -1), 1) + 1) * Float.pi / 4
        // ln(100): the level falls by 40 dB over `decay` seconds.
        let decaySamples = max(1, blip.decay * sampleRate)
        voices[chosen] = Voice(
            isActive: true,
            phase: 0,
            increment: min(blip.frequency / sampleRate, 0.45),
            level: 0,
            peak: blip.amplitude,
            attackStep: blip.amplitude / Float(attackSamples),
            attackRemaining: attackSamples,
            decayFactor: exp(-4.605_17 / decaySamples),
            delay: max(0, Int(blip.delay * sampleRate)),
            gainLeft: cos(angle),
            gainRight: sin(angle),
            brightness: min(max(blip.brightness, 0), 1)
        )
    }

    private func renderVoice(
        _ voice: inout Voice,
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        mono: Bool
    ) {
        var frame = 0
        if voice.delay > 0 {
            let wait = min(voice.delay, frameCount)
            voice.delay -= wait
            frame = wait
        }

        var phase = voice.phase
        var level = voice.level
        var attackRemaining = voice.attackRemaining
        let gainLeft = mono ? (voice.gainLeft + voice.gainRight) * 0.5 : voice.gainLeft
        let gainRight = voice.gainRight
        let twoPi = 2 * Float.pi
        while frame < frameCount {
            if attackRemaining > 0 {
                level += voice.attackStep
                attackRemaining -= 1
            } else {
                level *= voice.decayFactor
            }

            let sine = sin(twoPi * phase)
            // A triangle in phase with the sine: 0 at 0, 1 at ¼, −1 at ¾.
            var shifted = phase + 0.25
            if shifted >= 1 { shifted -= 1 }
            let triangle = 1 - 4 * abs(shifted - 0.5)
            let sample = (sine + voice.brightness * (triangle - sine)) * level

            if mono {
                left[frame] += sample * gainLeft
            } else {
                left[frame] += sample * gainLeft
                right[frame] += sample * gainRight
            }

            phase += voice.increment
            if phase >= 1 { phase -= 1 }
            frame += 1
        }

        voice.phase = phase
        voice.level = level
        voice.attackRemaining = attackRemaining
        if voice.delay == 0, attackRemaining == 0, level < voice.peak * 0.000_5 {
            voice.isActive = false
        }
    }

    /// A gentle peak limiter: an envelope follower with instant attack and a
    /// 150 ms release turns the mix down whenever it passes the threshold,
    /// and a `tanh` curve rounds off anything left over. Dense passages get
    /// quieter instead of harsh.
    private func limit(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        var follower = envelope.pointee
        for frame in 0..<frameCount {
            let peak = max(abs(left[frame]), abs(right?[frame] ?? 0))
            follower = peak > follower ? peak : follower * releaseFactor
            let gain = follower > threshold ? threshold / follower : 1
            left[frame] = tanh(left[frame] * gain)
            if let right {
                right[frame] = tanh(right[frame] * gain)
            }
        }
        envelope.pointee = follower
    }
}
