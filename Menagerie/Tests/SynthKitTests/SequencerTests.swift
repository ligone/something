import SynthKit
import XCTest

final class SequencerTests: XCTestCase {
    /// Runs a sequencer for `seconds` and collects every event, as the engine would.
    private func events(seed: UInt64, seconds: Double, tempo: Double = 84, swing: Double = 0.1, sampleRate: Double = 48_000) -> [SynthSequencer.Event] {
        let sequencer = SynthSequencer(sampleRate: sampleRate, tempo: tempo, seed: seed)
        sequencer.setSwing(swing)
        sequencer.start(at: 1_000)
        var collected: [SynthSequencer.Event] = []
        let end = Int64(seconds * sampleRate) + 1_000
        var now: Int64 = 1_000
        while now < end {
            sequencer.emitEvents(through: now) { collected.append($0) }
            now = min(sequencer.nextEventTime, end)
        }
        sequencer.stop(at: end) { collected.append($0) }
        return collected
    }

    func testSequencerIsDeterministic() {
        let first = events(seed: 5, seconds: 90)
        let second = events(seed: 5, seconds: 90)
        XCTAssertGreaterThan(first.count, 500)
        XCTAssertEqual(first, second, "the same seed must play the same piece")
        XCTAssertNotEqual(first, events(seed: 6, seconds: 90), "a different seed plays a different piece")
    }

    func testEventsLandExactlyOnTheSixteenthNoteGrid() {
        // 120 BPM at 48 kHz: a sixteenth is exactly 6 000 samples.
        let straight = events(seed: 1, seconds: 30, tempo: 120, swing: 0)
        for event in straight where event.kind == .noteOn {
            XCTAssertEqual((event.time - 1_000) % 6_000, 0, "note-on at \(event.time) is off the grid")
        }
        // With swing, every other sixteenth is late by the swing fraction.
        let swung = events(seed: 1, seconds: 30, tempo: 120, swing: 0.25)
        for event in swung where event.kind == .noteOn {
            let offset = (event.time - 1_000) % 12_000
            XCTAssertTrue(offset == 0 || offset == 6_000 + 1_500, "unexpected swing offset \(offset)")
        }
    }

    func testEventsAreOrderedAndEveryNoteIsReleased() {
        let all = events(seed: 9, seconds: 120)
        var previousTime: Int64 = .min
        var sounding: [Int: Int] = [:]
        for event in all {
            XCTAssertGreaterThanOrEqual(event.time, previousTime, "events must come in time order")
            previousTime = event.time
            switch event.kind {
            case .noteOn:
                XCTAssertNil(sounding[event.note], "note \(event.note) started twice without a release")
                sounding[event.note] = 1
                XCTAssertTrue((0.2 ... 1).contains(event.velocity))
            case .noteOff:
                XCTAssertNotNil(sounding[event.note], "note \(event.note) released but never started")
                sounding[event.note] = nil
            }
        }
        XCTAssertTrue(sounding.isEmpty, "stop must release everything")
    }

    func testEveryNoteBelongsToTheKeyAndItsRegister() {
        for seed: UInt64 in 0 ..< 6 {
            let tonic = [2, 9, 4, 7, 0, 5][Int(seed % 6)]
            // Natural minor plus the Dorian sixth: the collection every progression draws from.
            let allowed: Set<Int> = [0, 2, 3, 5, 7, 8, 9, 10]
            for event in events(seed: seed, seconds: 60) where event.kind == .noteOn {
                XCTAssertTrue(allowed.contains(((event.note - tonic) % 12 + 12) % 12), "note \(event.note) is outside the key (seed \(seed))")
                switch event.part {
                case .bass: XCTAssertTrue((36 ... 47).contains(event.note))
                case .pad: XCTAssertTrue((50 ... 72).contains(event.note), "pad note \(event.note) outside its register")
                case .arpeggio: XCTAssertGreaterThanOrEqual(event.note, 67)
                }
            }
        }
    }

    func testPadVoicingsHaveNoSemitoneClashes() {
        var pad: Set<Int> = []
        for event in events(seed: 4, seconds: 120) where event.part == .pad {
            if event.kind == .noteOn { pad.insert(event.note) } else { pad.remove(event.note) }
            let sorted = pad.sorted()
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                XCTAssertGreaterThan(b - a, 1, "pad voicing \(sorted) has a semitone clash")
            }
        }
    }

    func testEchoesSnapToTheNearestNoteValue() {
        // At 84 BPM a beat lasts 0.714 s: 0.36 s is nearest an eighth, 0.5 s a dotted eighth.
        let beat = 60.0 / 84
        XCTAssertEqual(SynthSequencer.syncedDelayTime(0.36, tempo: 84), beat / 2, accuracy: 1e-12)
        XCTAssertEqual(SynthSequencer.syncedDelayTime(0.5, tempo: 84), beat * 0.75, accuracy: 1e-12)
        XCTAssertEqual(SynthSequencer.syncedDelayTime(0.02, tempo: 84), beat / 4, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(SynthSequencer.syncedDelayTime(1.5, tempo: 50), 1.5, "never beyond the delay line")
    }

    func testTempoSetsTheStepLength() {
        let sequencer = SynthSequencer(sampleRate: 48_000, tempo: 90)
        XCTAssertEqual(sequencer.samplesPerStep, 8_000, accuracy: 1e-9)
        sequencer.setTempo(1_000)
        XCTAssertEqual(sequencer.tempo, SynthSequencer.tempoRange.upperBound)
    }
}
