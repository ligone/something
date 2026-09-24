import SynthKit
import XCTest

final class ModelTests: XCTestCase {
    func testNoteSetHoldsEveryMIDINote() {
        var set = SynthNoteSet()
        for note in stride(from: 0, to: 128, by: 3) { set.insert(note) }
        XCTAssertEqual(set.count, 43)
        XCTAssertTrue(set.contains(0))
        XCTAssertTrue(set.contains(63))
        XCTAssertTrue(set.contains(126))
        XCTAssertFalse(set.contains(127))
        set.remove(63)
        XCTAssertFalse(set.contains(63))
        set.insert(-1)
        set.insert(128)
        XCTAssertEqual(set.count, 42, "out-of-range notes are ignored")
        XCTAssertEqual(SynthNoteSet([60, 64, 67]).notes, [60, 64, 67])
        set.removeAll()
        XCTAssertTrue(set.isEmpty)
    }

    func testSanitizedPatchesStayInRange() {
        var patch = SynthPreset.pluck.patch
        patch.osc1.octave = -9
        patch.osc2.detune = .nan
        patch.filter.cutoff = 1e9
        patch.filter.resonance = -1
        patch.ampEnvelope.attack = -5
        patch.lfo.rate = .infinity
        patch.effects.delayFeedback = 3
        patch.level = 99
        let clean = patch.sanitized()
        XCTAssertEqual(clean.osc1.octave, -2)
        XCTAssertEqual(clean.osc2.detune, 0)
        XCTAssertEqual(clean.filter.cutoff, 20_000)
        XCTAssertEqual(clean.filter.resonance, 0)
        XCTAssertEqual(clean.ampEnvelope.attack, SynthPatch.Envelope.attackRange.lowerBound)
        XCTAssertEqual(clean.lfo.rate, 1)
        XCTAssertEqual(clean.effects.delayFeedback, 0.95)
        XCTAssertEqual(clean.level, 1.5)
        XCTAssertEqual(SynthPreset.warmPad.patch.sanitized(), SynthPreset.warmPad.patch, "presets are already in range")
    }

    func testPresetsAreDistinctAndFindable() {
        XCTAssertEqual(Set(SynthPreset.all.map(\.id)).count, SynthPreset.all.count)
        for preset in SynthPreset.all {
            XCTAssertEqual(SynthPreset.named(preset.id), preset)
            XCTAssertEqual(preset.patch.sanitized(), preset.patch, "\(preset.name) has out-of-range values")
        }
        XCTAssertNil(SynthPreset.named("missing"))
    }

    func testChordSymbolsAreSpelledForReading() {
        XCTAssertEqual(SynthChordSymbol(root: 2, quality: .minor9).name, "Dm9")
        XCTAssertEqual(SynthChordSymbol(root: 10, quality: .major7).name, "B♭maj7")
        XCTAssertEqual(SynthChordSymbol(root: 17, quality: .major7Sharp11).name, "Fmaj7♯11")
    }

    func testLFOShapesShareTheirPhase() {
        for shape in LFOShape.allCases {
            var lfo = SynthLFO(shape: shape)
            XCTAssertEqual(lfo.value, 0, accuracy: 1e-6)
            lfo.advance(seconds: 0.25, rate: 1)
            XCTAssertEqual(lfo.value, 1, accuracy: 1e-6, "\(shape) peaks a quarter cycle in")
            lfo.advance(seconds: 0.5, rate: 1)
            XCTAssertEqual(lfo.value, -1, accuracy: 1e-6, "\(shape) troughs three quarters in")
            lfo.advance(seconds: 10.25, rate: 1)
            XCTAssertEqual(lfo.phase, 0, accuracy: 1e-9)
        }
    }
}
