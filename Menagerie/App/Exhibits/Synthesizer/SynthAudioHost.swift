import AVFoundation
import SynthKit

/// Hosts a `SynthEngine` in Core Audio.
///
/// An `AVAudioEngine` pulls stereo, non-interleaved Float32 audio from an `AVAudioSourceNode`
/// whose render block calls straight into the synth, at the output device's own sample rate so
/// nothing is resampled. Only the output side of the engine is used: the input node is never
/// touched, so the app never asks for microphone access.
///
/// If there is no usable output device (a headless machine, for instance), the synth runs on a
/// timer instead, silently, so the visualizers still come alive.
@MainActor
final class SynthAudioHost {
    /// The running synth, or `nil` while stopped.
    private(set) var synth: SynthEngine?
    /// Whether audio actually reaches an output device.
    private(set) var isOutputAvailable = false
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var offlineClock: SynthOfflineClock?
    private var configurationObserver: NSObjectProtocol?

    /// Sample rate of the running synth, or 0 while stopped.
    var sampleRate: Double { synth?.sampleRate ?? 0 }

    /// Creates a synth and starts rendering it.
    ///
    /// - Parameter onConfigurationChange: Called on the main actor when the output device changes
    ///   (AVAudioEngine stops itself then; the caller should start again).
    func start(patch: SynthPatch, masterGain: Double, tempo: Double, onConfigurationChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        let engine = AVAudioEngine()
        let deviceRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = deviceRate > 0 ? deviceRate : 48_000
        let synth = SynthEngine(sampleRate: sampleRate, patch: patch, masterGain: masterGain)
        synth.setTempo(tempo)
        self.synth = synth

        if let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) {
            let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: synth))
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
            do {
                try engine.start()
                self.engine = engine
                sourceNode = node
                isOutputAvailable = true
                configurationObserver = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange,
                    object: engine,
                    queue: .main
                ) { _ in
                    Task { @MainActor in onConfigurationChange() }
                }
                return
            } catch {
                engine.detach(node)
            }
        }

        // No output device: keep the synth running for the visualizers.
        let clock = SynthOfflineClock(synth: synth)
        clock.start()
        offlineClock = clock
        isOutputAvailable = false
    }

    /// Stops audio and releases the graph. Safe to call when already stopped.
    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        if let engine {
            // `stop()` waits for the render thread to leave the callback, so the synth can go.
            engine.stop()
            if let sourceNode { engine.detach(sourceNode) }
        }
        offlineClock?.stop()
        offlineClock = nil
        sourceNode = nil
        engine = nil
        synth = nil
        isOutputAvailable = false
    }

    /// The real-time render callback.
    ///
    /// Built in a `nonisolated` context so the closure carries no actor isolation: Core Audio
    /// calls it on its I/O thread, where it must not allocate, lock or message Objective-C. It
    /// only unpacks the buffer list and calls `SynthEngine.render`, which honors the same rules.
    nonisolated private static func renderBlock(for synth: SynthEngine) -> AVAudioSourceNodeRenderBlock {
        return { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            if buffers.count >= 2,
               let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
               let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                synth.render(frameCount: Int(frameCount), left: left, right: right)
            } else {
                for buffer in buffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
            }
            return noErr
        }
    }
}

/// Renders a synth on a timer, in step with the wall clock, and throws the audio away. Used when
/// no output device is available so the visualizers still have a signal to show.
///
/// `@unchecked Sendable`: the buffers and `lastTick` are touched only on the clock's private
/// serial queue; `timer` only on the main actor.
final class SynthOfflineClock: @unchecked Sendable {
    private let synth: SynthEngine
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let queue = DispatchQueue(label: "Menagerie.Synthesizer.OfflineClock", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var lastTick: UInt64 = 0

    init(synth: SynthEngine) {
        self.synth = synth
        capacity = max(Int(synth.sampleRate * 0.1), 1)
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [self] in tick() }
        self.timer = timer
        timer.resume()
    }

    /// Cancels the timer, which also releases the handler's reference to the clock.
    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastTick == 0 ? 0.01 : Double(now &- lastTick) / 1e9
        lastTick = now
        let frames = min(Int(elapsed * synth.sampleRate), capacity)
        if frames > 0 {
            synth.render(frameCount: frames, left: left, right: right)
        }
    }
}
