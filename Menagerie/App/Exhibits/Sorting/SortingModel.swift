import Foundation
import Observation
import QuartzCore
import SortKit

/// How the stage draws the array.
enum SortingStyle: String, CaseIterable, Identifiable {
    case bars
    case dots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: "Bars"
        case .dots: "Dots"
        }
    }
}

/// Everything the Sound of Sorting exhibit shows and plays: the settings, one
/// lane per algorithm on stage (four in a race), the playback clock and the
/// sonification.
///
/// Traces are built off the main actor the moment the settings change, so
/// pressing Play is instant even for a million-step bubble sort.
@MainActor
@Observable
final class SortingModel {
    static let sizeRange = 8...1_024
    static let speedRange = 1.0...50_000.0
    static let defaultRace: [SortAlgorithm] = [.quick, .merge, .heap, .radixLSD]

    // MARK: Settings

    private(set) var algorithm = SortAlgorithm.quick
    private(set) var input = SortInput.random
    private(set) var size = 128
    private(set) var isRacing = false
    private(set) var raceAlgorithms = SortingModel.defaultRace
    private(set) var isSoundOn = false
    private(set) var volume = 0.7
    /// Steps per second, per lane.
    var speed = 160.0
    var style = SortingStyle.bars

    // MARK: State

    /// One lane, or four when racing.
    private(set) var lanes: [SortingLane] = []
    private(set) var isPlaying = false

    @ObservationIgnored private var seed: UInt64
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick: CFTimeInterval = 0
    @ObservationIgnored private var stepBudget = 0.0
    @ObservationIgnored private var touches: [SortTouch] = []
    @ObservationIgnored private var passed: [Int] = []
    @ObservationIgnored private var synth: SortingBlipSynth?

    /// Cheap on purpose: SwiftUI may create and discard models while it
    /// rebuilds views. The heavy work starts in `appear()`.
    init() {
        seed = AppEnvironment.isCaptureTour ? 0x50_4F_52_54 : UInt64.random(in: 0...UInt64.max)
        rebuildLanes()
    }

    // MARK: Derived state

    var primaryLane: SortingLane? { lanes.first }

    /// True once every lane's trace is ready.
    var isPrepared: Bool {
        !lanes.isEmpty && lanes.allSatisfy(\.isPrepared)
    }

    /// True once every lane is sorted and verified.
    var isFinished: Bool {
        !lanes.isEmpty && lanes.allSatisfy { $0.phase == .sorted }
    }

    /// True once any lane has taken a step.
    var hasStarted: Bool {
        lanes.contains { $0.phase != .waiting }
    }

    /// A lane's finishing place in a race, once it has finished. Every lane
    /// advances by the same number of steps per tick, so the lane with fewer
    /// steps always finishes first, and ties are true ties.
    func place(of lane: SortingLane) -> Int? {
        guard lane.phase == .verifying || lane.phase == .sorted, let steps = lane.totalSteps else { return nil }
        return 1 + lanes.filter { ($0.totalSteps ?? .max) < steps }.count
    }

    // MARK: Lifecycle

    func appear() {
        if AppEnvironment.isCaptureTour {
            // Screenshots: start at once, silently, at a pace that is
            // mid-sort when the tour takes its picture a few seconds in.
            prepareNow()
            let steps = Double(primaryLane?.totalSteps ?? 1_000)
            speed = min(max(steps / 11, 20), Self.speedRange.upperBound)
            play()
        } else if !isPrepared {
            prepareTraces(debounce: false)
        }
    }

    func disappear() {
        isPlaying = false
        stopTicking()
        prepareTask?.cancel()
        synth?.stop()
    }

    // MARK: Playback

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// Plays, or when everything is sorted, shuffles and plays again.
    func play() {
        if isFinished {
            reshuffle(debounce: false)
        }
        for index in lanes.indices {
            lanes[index].clearLatest()
        }
        isPlaying = true
        // Take the first step right away, even at one step per second.
        stepBudget = 1
        startTicking()
    }

    func pause() {
        isPlaying = false
    }

    /// Pauses and applies exactly one operation per lane.
    func step() {
        pause()
        if !isPrepared {
            prepareNow()
        }
        for index in lanes.indices {
            touches.removeAll(keepingCapacity: true)
            lanes[index].advance(steps: 1, touches: &touches)
            if index == 0 {
                sonify(touches, lane: lanes[0], frame: 0)
            }
        }
        startTicking()
    }

    /// Rewinds to the same unsorted array.
    func reset() {
        pause()
        stepBudget = 0
        for index in lanes.indices {
            lanes[index].rewind()
        }
    }

    /// Pauses and deals a fresh array.
    func shuffle() {
        pause()
        reshuffle(debounce: false)
    }

    // MARK: Settings

    func select(_ algorithm: SortAlgorithm) {
        guard algorithm != self.algorithm else { return }
        self.algorithm = algorithm
        if !isRacing {
            rebuild(debounce: false)
        }
    }

    func select(_ input: SortInput) {
        guard input != self.input else { return }
        self.input = input
        rebuild(debounce: false)
    }

    func setSize(_ size: Int) {
        let size = min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        guard size != self.size else { return }
        self.size = size
        // Sliders send a stream of sizes; wait for a pause before tracing.
        rebuild(debounce: true)
    }

    func setRacing(_ racing: Bool) {
        guard racing != isRacing else { return }
        isRacing = racing
        rebuild(debounce: false)
    }

    func setRaceAlgorithm(_ algorithm: SortAlgorithm, lane: Int) {
        guard raceAlgorithms.indices.contains(lane), raceAlgorithms[lane] != algorithm else { return }
        raceAlgorithms[lane] = algorithm
        if isRacing {
            rebuild(debounce: false)
        }
    }

    func setSoundOn(_ on: Bool) {
        guard on != isSoundOn else { return }
        isSoundOn = on
        if on {
            let synth = self.synth ?? SortingBlipSynth()
            synth.volume = Float(volume)
            self.synth = synth
            // A soft two-note chime says hello and starts the audio engine.
            synth.play([
                chime(level: 0.45, delay: 0),
                chime(level: 0.75, delay: 0.07),
            ])
        } else {
            synth?.stop()
        }
    }

    func setVolume(_ volume: Double) {
        self.volume = min(max(volume, 0), 1)
        synth?.volume = Float(self.volume)
    }

    // MARK: Building lanes

    /// Deals the current input into fresh lanes, keeping playback going if it
    /// was, and starts tracing them.
    private func rebuild(debounce: Bool) {
        let wasPlaying = isPlaying
        rebuildLanes()
        prepareTraces(debounce: debounce)
        if wasPlaying {
            stepBudget = 0
            startTicking()
        }
    }

    private func reshuffle(debounce: Bool) {
        seed = UInt64.random(in: 0...UInt64.max)
        rebuild(debounce: debounce)
    }

    private func rebuildLanes() {
        let values = input.generate(count: size, seed: seed)
        let algorithms = isRacing ? raceAlgorithms : [algorithm]
        lanes = algorithms.enumerated().map { index, algorithm in
            SortingLane(id: index, algorithm: algorithm, input: values)
        }
        stepBudget = 0
    }

    /// Builds the traces on a background thread and installs them if the
    /// lanes haven't changed meanwhile.
    private func prepareTraces(debounce: Bool) {
        prepareTask?.cancel()
        generation += 1
        let generation = self.generation
        let algorithms = lanes.map(\.algorithm)
        let values = lanes.first?.input ?? []

        prepareTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(90))
            }
            guard !Task.isCancelled else { return }
            let traces = await Task.detached(priority: .userInitiated) {
                algorithms.map { $0.trace(of: values) }
            }.value
            guard !Task.isCancelled else { return }
            self?.install(traces, generation: generation)
        }
    }

    private func install(_ traces: [SortTrace], generation: Int) {
        guard generation == self.generation, traces.count == lanes.count else { return }
        for index in lanes.indices {
            lanes[index].install(traces[index])
        }
        if isPlaying {
            startTicking()
        }
    }

    /// Traces synchronously, for a Step pressed before the background work
    /// is done (and for the screenshot tour, which wants determinism).
    private func prepareNow() {
        prepareTask?.cancel()
        generation += 1
        for index in lanes.indices where !lanes[index].isPrepared {
            lanes[index].install(lanes[index].algorithm.trace(of: lanes[index].input))
        }
    }

    // MARK: The clock

    private func startTicking() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    /// One frame: replay some steps, move the sweeps, fade the glows, play
    /// the sounds, and stop the clock once nothing is moving.
    private func tick() {
        let now = CACurrentMediaTime()
        // Clamp so a stall (a window drag, a debugger pause) doesn't turn
        // into one giant leap.
        let elapsed = min(max(now - lastTick, 0), 1.0 / 15.0)
        lastTick = now

        if isPlaying, isPrepared {
            stepBudget += speed * elapsed
            let steps = Int(stepBudget)
            stepBudget -= Double(steps)
            if steps > 0 {
                for index in lanes.indices {
                    touches.removeAll(keepingCapacity: true)
                    lanes[index].advance(steps: steps, touches: &touches)
                    if index == 0 {
                        sonify(touches, lane: lanes[0], frame: steps > 1 ? elapsed : 0)
                    }
                }
            }
        }

        for index in lanes.indices where lanes[index].phase == .verifying {
            passed.removeAll(keepingCapacity: true)
            let count = Double(lanes[index].input.count)
            let duration = 0.9 + 0.5 * count / Double(Self.sizeRange.upperBound)
            lanes[index].advanceSweep(by: count / duration * elapsed, passed: &passed)
            if index == 0 {
                sonifySweep(passed, lane: lanes[0], frame: elapsed)
            }
        }

        // Glows fade with a time constant of 0.12 s; the sweep's green, 0.35 s.
        let normal = Float(exp(-elapsed / 0.12))
        let lingering = Float(exp(-elapsed / 0.35))
        var glowing = false
        for index in lanes.indices {
            if lanes[index].fade(normal: normal, lingering: lingering) {
                glowing = true
            }
        }

        if isPlaying, isFinished {
            isPlaying = false
        }
        let sweeping = lanes.contains { $0.phase == .verifying }
        if !isPlaying, !sweeping, !glowing {
            stopTicking()
        }
    }

    // MARK: Sonification

    /// The most tones a single frame may start: about 360 a second, which
    /// sounds like a shimmer rather than static.
    private static let tonesPerFrame = 6

    /// Turns a frame's touches into blips: at most one per index and
    /// `tonesPerFrame` in all, picked evenly through the frame and spread
    /// across its duration in the order they happened.
    private func sonify(_ touches: [SortTouch], lane: SortingLane, frame: Double) {
        guard isSoundOn, let synth, !touches.isEmpty else { return }
        let count = touches.count
        let picks = min(count, Self.tonesPerFrame)
        var chosen: [(touch: SortTouch, position: Int)] = []
        for pick in 0..<picks {
            let position = count <= Self.tonesPerFrame ? pick : (2 * pick + 1) * count / (2 * picks)
            let touch = touches[position]
            if !chosen.contains(where: { $0.touch.index == touch.index }) {
                chosen.append((touch: touch, position: position))
            }
        }
        let loudness = 1 / Double(chosen.count).squareRoot()
        let blips = chosen.map { touch, position in
            blip(
                value: touch.value,
                index: touch.index,
                lane: lane,
                highlight: SortingHighlight(touch.kind),
                loudness: loudness,
                delay: frame * Double(position) / Double(count)
            )
        }
        synth.play(blips)
    }

    /// The verification sweep's rising glissando: a few of the bars passed
    /// this frame, in order.
    private func sonifySweep(_ indices: [Int], lane: SortingLane, frame: Double) {
        guard isSoundOn, let synth, !indices.isEmpty else { return }
        let values = lane.values
        let picks = min(indices.count, 3)
        let blips = (0..<picks).map { pick in
            let position = (2 * pick + 1) * indices.count / (2 * picks)
            let index = indices[position]
            return blip(
                value: values[index],
                index: index,
                lane: lane,
                highlight: .verified,
                loudness: 0.8 / Double(picks).squareRoot(),
                delay: frame * Double(position) / Double(indices.count)
            )
        }
        synth.play(blips)
    }

    /// Pitch rises exponentially with the value, from 120 Hz to 1.5 kHz, so
    /// equal steps in value sound like equal musical intervals. Pan follows
    /// the index. Low notes ring a little longer (80 ms against 35 ms) and a
    /// little louder, which evens out how loud they seem.
    private func blip(
        value: Int,
        index: Int,
        lane: SortingLane,
        highlight: SortingHighlight,
        loudness: Double,
        delay: Double
    ) -> SortingBlip {
        let level = lane.level(of: value)
        let frequency = 120 * pow(1_500.0 / 120.0, level)
        let span = Double(max(1, lane.input.count - 1))
        let pan = (Double(index) / span * 2 - 1) * 0.7
        let decay = 0.080 - 0.045 * level
        let brightness: Double = switch highlight {
        case .compare: 0.12
        case .move: 0.5
        case .read: 0.05
        case .verified: 0.3
        case .mismatch: 1
        }
        let amplitude = 0.3 * loudness * (1.12 - 0.3 * level)
        return SortingBlip(
            frequency: Float(frequency),
            amplitude: Float(amplitude),
            pan: Float(pan),
            decay: Float(decay),
            brightness: Float(brightness),
            delay: Float(delay)
        )
    }

    private func chime(level: Double, delay: Double) -> SortingBlip {
        SortingBlip(
            frequency: Float(120 * pow(1_500.0 / 120.0, level)),
            amplitude: 0.16,
            pan: 0,
            decay: 0.22,
            brightness: 0.2,
            delay: Float(delay)
        )
    }
}
