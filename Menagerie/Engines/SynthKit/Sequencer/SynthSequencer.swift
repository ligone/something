import Foundation

/// A generative composer that plays the synthesizer by itself: slow extended chords with smooth
/// voice leading, a root-note bass line, and a sparkling arpeggio over the top.
///
/// Music is organized in 8-bar sections of sixteenth-note steps. Each section picks a four-chord
/// progression, a chord rhythm (one or two bars per chord), an arpeggio contour and rhythm, and a
/// bass pattern, all from a seeded `SynthRandom`, so the same seed always plays the same piece.
///
/// Scheduling is sample-accurate: every event carries the absolute sample time at which it
/// sounds. The engine asks for `nextEventTime`, renders up to it, then calls
/// `emitEvents(through:_:)`. The sequencer is allocation-free after `init` and safe to drive from
/// the audio thread.
public final class SynthSequencer {
    /// A note event produced by the sequencer.
    public struct Event: Equatable, Sendable {
        public enum Kind: UInt8, Sendable { case noteOn, noteOff }
        public enum Part: UInt8, Sendable { case bass, pad, arpeggio }

        public var kind: Kind
        public var note: Int
        public var velocity: Float
        /// Absolute sample time at which the event sounds.
        public var time: Int64
        public var part: Part
    }

    /// Allowed tempo range in beats per minute.
    public static let tempoRange: ClosedRange<Double> = 50 ... 160

    // Registers (MIDI notes) for the three parts. Computed rather than stored so that nothing
    // lazily initialized is ever first touched on the audio thread.
    static var bassRange: ClosedRange<Int32> { 36 ... 47 }
    static var padRange: ClosedRange<Int32> { 50 ... 72 }
    static var arpeggioRange: ClosedRange<Int32> { 67 ... 88 }

    private static var pendingCapacity: Int { 32 }
    private static var toneCapacity: Int { 32 }
    private static var barsPerSection: Int { 8 }

    /// The key of the piece for a seed: D, A, E, G, C or F minor.
    private static func tonic(for seed: UInt64) -> Int32 {
        switch seed % 6 {
        case 0: return 2
        case 1: return 9
        case 2: return 4
        case 3: return 7
        case 4: return 0
        default: return 5
        }
    }

    /// Sample rate the event times are expressed in.
    public let sampleRate: Double
    /// Whether the sequencer is producing events.
    public private(set) var isPlaying = false
    /// Seed of the piece being played.
    public private(set) var seed: UInt64
    /// Tempo in beats per minute; changes take effect from the next step.
    public private(set) var tempo: Double
    /// Delay applied to every other sixteenth, as a fraction of a step.
    public private(set) var swing: Double = 0.1
    /// The chord currently sounding, for display.
    public private(set) var currentChord: SynthChordSymbol?
    /// Index of the current sixteenth-note step since `start`.
    public private(set) var stepIndex = 0

    private var random: SynthRandom
    private var tonic: Int32 = 2
    private var gridTime: Double = 0
    private var sectionNumber = -1

    // The current section's plan.
    private var progression = 0
    private var barsPerChord = 1
    private var arpeggioPattern = 0
    private var arpeggioRhythm = 0
    private var bassPattern = 0
    private var arpeggioStartBar = 0

    // Sounding pad chord and its voice-leading history.
    private var padNotes = SIMD4<Int32>(repeating: -1)
    private var hasPad = false
    private var chord = SynthHarmony.Chord(root: 0, quality: .minor9)

    // Pending note-offs for the bass and arpeggio.
    private let pendingTimes: UnsafeMutablePointer<Int64>
    private let pendingNotes: UnsafeMutablePointer<Int32>
    private let pendingParts: UnsafeMutablePointer<Event.Part>
    private var pendingCount = 0

    // Chord tones inside the arpeggio register, ascending.
    private let arpeggioTones: UnsafeMutablePointer<Int32>
    private var arpeggioToneCount = 0

    /// Creates a stopped sequencer.
    public init(sampleRate: Double, tempo: Double = 84, seed: UInt64 = 0) {
        self.sampleRate = sampleRate > 0 && sampleRate.isFinite ? sampleRate : 48_000
        self.tempo = SynthMath.sanitize(tempo, Self.tempoRange, fallback: 84)
        self.seed = seed
        random = SynthRandom(seed: seed)
        pendingTimes = .allocate(capacity: Self.pendingCapacity)
        pendingNotes = .allocate(capacity: Self.pendingCapacity)
        pendingParts = .allocate(capacity: Self.pendingCapacity)
        arpeggioTones = .allocate(capacity: Self.toneCapacity)
        pendingTimes.initialize(repeating: 0, count: Self.pendingCapacity)
        pendingNotes.initialize(repeating: 0, count: Self.pendingCapacity)
        pendingParts.initialize(repeating: .bass, count: Self.pendingCapacity)
        arpeggioTones.initialize(repeating: 0, count: Self.toneCapacity)
    }

    deinit {
        pendingTimes.deallocate()
        pendingNotes.deallocate()
        pendingParts.deallocate()
        arpeggioTones.deallocate()
    }

    /// Length of one sixteenth-note step in samples at the current tempo.
    public var samplesPerStep: Double {
        60 / tempo / 4 * sampleRate
    }

    /// Sets the tempo (clamped to `tempoRange`).
    public func setTempo(_ bpm: Double) {
        tempo = SynthMath.sanitize(bpm, Self.tempoRange, fallback: tempo)
    }

    /// Sets the swing amount (0 … 0.5 of a step).
    public func setSwing(_ amount: Double) {
        swing = SynthMath.sanitize(amount, 0 ... 0.5, fallback: swing)
    }

    /// The musical note value nearest to `seconds` at `tempo` (a sixteenth up to a whole note,
    /// including dotted values), so echoes of the generative player land on its grid.
    /// Nearness is measured in ratio, not in seconds, as the ear hears it.
    public static func syncedDelayTime(_ seconds: Double, tempo: Double, maximum: Double = 1.5) -> Double {
        guard seconds > 0, seconds.isFinite, tempo > 0, tempo.isFinite else { return seconds }
        let beat = 60 / tempo
        let multiples = SIMD8<Double>(0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4)
        var best = seconds
        var bestDistance = Double.infinity
        for lane in 0 ..< 8 {
            let candidate = beat * multiples[lane]
            guard candidate <= maximum else { continue }
            let distance = abs(log(candidate / seconds))
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    /// Starts a new piece whose first event sounds at sample `time`.
    public func start(at time: Int64, seed newSeed: UInt64? = nil) {
        if let newSeed { seed = newSeed }
        random = SynthRandom(seed: seed)
        tonic = Self.tonic(for: seed)
        gridTime = Double(time)
        stepIndex = 0
        sectionNumber = -1
        pendingCount = 0
        padNotes = SIMD4<Int32>(repeating: -1)
        hasPad = false
        arpeggioToneCount = 0
        currentChord = nil
        isPlaying = true
    }

    /// Stops, emitting note-offs at `time` for everything still sounding.
    public func stop(at time: Int64, _ emit: (Event) -> Void) {
        guard isPlaying else { return }
        for i in 0 ..< pendingCount {
            emit(Event(kind: .noteOff, note: Int(pendingNotes[i]), velocity: 0, time: time, part: pendingParts[i]))
        }
        pendingCount = 0
        if hasPad {
            for lane in 0 ..< 4 where padNotes[lane] >= 0 {
                emit(Event(kind: .noteOff, note: Int(padNotes[lane]), velocity: 0, time: time, part: .pad))
            }
        }
        hasPad = false
        padNotes = SIMD4<Int32>(repeating: -1)
        currentChord = nil
        isPlaying = false
    }

    /// Absolute sample time of the next event, or `Int64.max` when stopped.
    public var nextEventTime: Int64 {
        guard isPlaying else { return Int64.max }
        var next = currentStepTime
        for i in 0 ..< pendingCount where pendingTimes[i] < next {
            next = pendingTimes[i]
        }
        return next
    }

    /// Emits, in time order, every event due at or before sample `time`.
    /// Note-offs are emitted before note-ons that fall on the same sample.
    public func emitEvents(through time: Int64, _ emit: (Event) -> Void) {
        guard isPlaying else { return }
        while true {
            let stepTime = currentStepTime
            var earliest = -1
            for i in 0 ..< pendingCount where pendingTimes[i] <= time {
                if earliest < 0 || pendingTimes[i] < pendingTimes[earliest] { earliest = i }
            }
            if earliest >= 0 && pendingTimes[earliest] <= stepTime {
                let event = Event(kind: .noteOff, note: Int(pendingNotes[earliest]), velocity: 0, time: pendingTimes[earliest], part: pendingParts[earliest])
                removePending(at: earliest)
                emit(event)
            } else if stepTime <= time {
                performStep(at: stepTime, emit)
            } else {
                return
            }
        }
    }

    // MARK: - Composition

    /// Time of the step about to play, including swing on odd sixteenths.
    private var currentStepTime: Int64 {
        let swingOffset = stepIndex % 2 == 1 ? swing * samplesPerStep : 0
        return Int64((gridTime + swingOffset).rounded())
    }

    private func performStep(at time: Int64, _ emit: (Event) -> Void) {
        let stepLength = samplesPerStep
        let stepInBar = stepIndex % 16
        let bar = stepIndex / 16
        let barInSection = bar % Self.barsPerSection

        if stepInBar == 0 && barInSection == 0 { planSection() }
        if stepInBar == 0 && barInSection % barsPerChord == 0 {
            let slot = (barInSection / barsPerChord) % 4
            changeChord(to: SynthHarmony.chord(progression: progression, slot: slot), at: time, emit)
        }
        playBass(stepInBar: stepInBar, at: time, stepLength: stepLength, emit)
        if barInSection >= arpeggioStartBar {
            playArpeggio(stepInBar: stepInBar, barInSection: barInSection, at: time, stepLength: stepLength, emit)
        }

        stepIndex += 1
        gridTime += stepLength
    }

    /// Picks the material for the next eight bars.
    private func planSection() {
        sectionNumber += 1
        if sectionNumber == 0 {
            progression = random.nextInt(below: 2)
            barsPerChord = 1
            arpeggioRhythm = 0
            arpeggioStartBar = 2
            bassPattern = 0
        } else {
            progression = (progression + 1 + random.nextInt(below: SynthHarmony.progressionCount - 1)) % SynthHarmony.progressionCount
            // Every third section breathes: long chords and a sparse arpeggio.
            let breathe = sectionNumber % 3 == 2
            barsPerChord = breathe || random.chance(0.25) ? 2 : 1
            arpeggioRhythm = breathe ? (random.chance(0.5) ? 0 : 4) : 1 + random.nextInt(below: SynthHarmony.rhythmCount - 1)
            arpeggioStartBar = 0
            bassPattern = breathe ? 0 : random.nextInt(below: SynthHarmony.bassPatternCount)
        }
        arpeggioPattern = random.nextInt(below: SynthHarmony.arpeggioPatternCount)
    }

    private func changeChord(to newChord: SynthHarmony.Chord, at time: Int64, _ emit: (Event) -> Void) {
        chord = newChord
        let rootClass = (tonic + newChord.root) % 12
        currentChord = SynthChordSymbol(root: Int(rootClass), quality: newChord.quality)

        // Pad: move to the nearest clash-free voicing, holding common tones instead of restriking.
        let voicing = Self.voicing(rootClass: rootClass, shape: newChord.quality.padShape, previous: hasPad ? padNotes : nil)
        if hasPad {
            for lane in 0 ..< 4 where padNotes[lane] >= 0 && !Self.contains(voicing, padNotes[lane]) {
                emit(Event(kind: .noteOff, note: Int(padNotes[lane]), velocity: 0, time: time, part: .pad))
            }
        }
        for lane in 0 ..< 4 where !(hasPad && Self.contains(padNotes, voicing[lane])) {
            let velocity = Float(0.4 + 0.08 * random.nextUnit())
            emit(Event(kind: .noteOn, note: Int(voicing[lane]), velocity: velocity, time: time, part: .pad))
        }
        padNotes = voicing
        hasPad = true

        // Arpeggio register: every chord tone between the range limits, ascending.
        let tones = newChord.quality.tones
        let toneCount = newChord.quality.toneCount
        arpeggioToneCount = 0
        var note = Self.arpeggioRange.lowerBound
        while note <= Self.arpeggioRange.upperBound && arpeggioToneCount < Self.toneCapacity {
            let interval = ((note - rootClass) % 12 + 12) % 12
            for lane in 0 ..< toneCount where tones[lane] % 12 == interval {
                arpeggioTones[arpeggioToneCount] = note
                arpeggioToneCount += 1
                break
            }
            note += 1
        }
    }

    private func playBass(stepInBar: Int, at time: Int64, stepLength: Double, _ emit: (Event) -> Void) {
        let pattern = SynthHarmony.bassPattern(bassPattern)
        for hit in 0 ..< pattern.count where Int(pattern.starts[hit]) == stepInBar {
            let rootClass = (tonic + chord.root) % 12
            let note = Self.bassRange.lowerBound + (rootClass - Self.bassRange.lowerBound % 12 + 12) % 12
            let velocity = Float(hit == 0 ? 0.62 : 0.48) + Float(0.06 * random.nextUnit())
            emit(Event(kind: .noteOn, note: Int(note), velocity: velocity, time: time, part: .bass))
            let length = (Double(pattern.lengths[hit]) - 0.15) * stepLength
            schedule(noteOff: note, part: .bass, at: time + Int64(length.rounded()))
        }
    }

    private func playArpeggio(stepInBar: Int, barInSection: Int, at time: Int64, stepLength: Double, _ emit: (Event) -> Void) {
        let rhythm = SynthHarmony.rhythm(arpeggioRhythm)
        guard (rhythm >> UInt16(stepInBar)) & 1 == 1, arpeggioToneCount > 0 else { return }

        let contour = SynthHarmony.arpeggioPattern(arpeggioPattern)
        var note = arpeggioTones[Int(contour[stepInBar]) % arpeggioToneCount]
        // Never double a note the pad is holding (they would share a voice): lift it an octave.
        if hasPad && Self.contains(padNotes, note) { note += 12 }

        // Accents on the beat, a swell across the section, and a little human unevenness.
        var velocity = 0.5
        switch stepInBar {
        case 0: velocity += 0.18
        case 8: velocity += 0.1
        case 4, 12: velocity += 0.06
        default: break
        }
        velocity += 0.08 * sin(Double.pi * Double(barInSection) / Double(Self.barsPerSection))
        velocity += 0.1 * (random.nextUnit() - 0.5)
        emit(Event(kind: .noteOn, note: Int(note), velocity: Float(min(max(velocity, 0.2), 1)), time: time, part: .arpeggio))

        // Hold until just before the next arpeggio note (at most two steps).
        var gap = 1
        while gap < 2 && (rhythm >> UInt16((stepInBar + gap) % 16)) & 1 == 0 { gap += 1 }
        let length = Double(gap) * stepLength * 0.85
        schedule(noteOff: note, part: .arpeggio, at: time + max(Int64(length.rounded()), 1))
    }

    private func schedule(noteOff note: Int32, part: Event.Part, at time: Int64) {
        guard pendingCount < Self.pendingCapacity else { return }
        pendingTimes[pendingCount] = time
        pendingNotes[pendingCount] = note
        pendingParts[pendingCount] = part
        pendingCount += 1
    }

    private func removePending(at index: Int) {
        pendingCount -= 1
        pendingTimes[index] = pendingTimes[pendingCount]
        pendingNotes[index] = pendingNotes[pendingCount]
        pendingParts[index] = pendingParts[pendingCount]
    }

    // MARK: - Voice leading

    /// Chooses the pad voicing for a chord: tries every inversion of `shape` in every octave that
    /// fits the pad register, rejects any with a semitone between neighboring voices, and keeps
    /// the one that moves least from `previous` (or sits nearest middle C when starting).
    static func voicing(rootClass: Int32, shape: SIMD4<Int32>, previous: SIMD4<Int32>?) -> SIMD4<Int32> {
        var best = SIMD4<Int32>(repeating: -1)
        var bestCost = Int32.max
        var inversion = shape
        for _ in 0 ..< 4 {
            let sorted = sort(inversion)
            let lowest = padRange.lowerBound - sorted[0]
            var base = lowest - ((lowest - rootClass) % 12 + 12) % 12
            if base < lowest { base += 12 }
            while base + sorted[3] <= padRange.upperBound {
                let candidate = sorted &+ base
                if !hasSemitoneClash(candidate) {
                    let cost: Int32
                    if let previous {
                        let moves = candidate &- sort(previous)
                        cost = abs(moves[0]) + abs(moves[1]) + abs(moves[2]) + abs(moves[3])
                    } else {
                        cost = abs(candidate[0] + candidate[3] - 124)
                    }
                    if cost < bestCost {
                        bestCost = cost
                        best = candidate
                    }
                }
                base += 12
            }
            // Next inversion: the lowest voice moves up an octave.
            inversion = SIMD4(sorted[1], sorted[2], sorted[3], sorted[0] + 12)
        }
        if bestCost == Int32.max {
            // No clash-free fit (cannot happen with the shapes above); fall back to root position.
            var base = padRange.lowerBound + ((rootClass - padRange.lowerBound) % 12 + 12) % 12
            if base + shape[3] > padRange.upperBound { base -= 12 }
            return shape &+ base
        }
        return best
    }

    private static func sort(_ v: SIMD4<Int32>) -> SIMD4<Int32> {
        var a = v[0], b = v[1], c = v[2], d = v[3]
        if a > b { swap(&a, &b) }
        if c > d { swap(&c, &d) }
        if a > c { swap(&a, &c) }
        if b > d { swap(&b, &d) }
        if b > c { swap(&b, &c) }
        return SIMD4(a, b, c, d)
    }

    private static func hasSemitoneClash(_ sorted: SIMD4<Int32>) -> Bool {
        sorted[1] - sorted[0] <= 1 || sorted[2] - sorted[1] <= 1 || sorted[3] - sorted[2] <= 1
    }

    private static func contains(_ v: SIMD4<Int32>, _ note: Int32) -> Bool {
        v[0] == note || v[1] == note || v[2] == note || v[3] == note
    }
}
