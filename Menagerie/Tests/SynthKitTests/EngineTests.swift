import Foundation
import SynthKit
import XCTest

final class EngineTests: XCTestCase {
    private let sampleRate = 48_000.0

    func testPlaysTheRequestedPitch() {
        let engine = SynthEngine(sampleRate: sampleRate, patch: testPatch(.sine), masterGain: 1)
        engine.noteOn(69, velocity: 1)
        let (left, right) = SignalAnalysis.render(engine, seconds: 1.2)
        let steady = Array(left[9_600...])
        XCTAssertEqual(SignalAnalysis.frequencyByZeroCrossings(steady, sampleRate: sampleRate), 440, accuracy: 0.5)
        XCTAssertEqual(left, right, "with zero stereo spread both channels carry the same signal")
        XCTAssertEqual(engine.status.activeVoices, 1)
        XCTAssertEqual(engine.status.heldNotes, SynthNoteSet([69]))
    }

    func testSilenceInGivesSilenceOut() {
        let engine = SynthEngine(sampleRate: sampleRate, patch: SynthPreset.warmPad.patch, masterGain: 1)
        let (left, right) = SignalAnalysis.render(engine, seconds: 1)
        XCTAssertTrue(left.allSatisfy { $0 == 0 })
        XCTAssertTrue(right.allSatisfy { $0 == 0 })
    }

    func testTailsDecayToSilenceOnceVoicesAreReleased() {
        var patch = SynthPreset.warmPad.patch
        patch.effects.delayFeedback = 0.6
        patch.effects.delayMix = 0.4
        patch.effects.reverbDecay = 3
        patch.effects.reverbMix = 0.6
        let engine = SynthEngine(sampleRate: sampleRate, patch: patch, masterGain: 1)
        for note in [48, 55, 60, 64, 67] { engine.noteOn(note, velocity: 0.9) }
        let sounding = SignalAnalysis.render(engine, seconds: 1.5)
        XCTAssertGreaterThan(SignalAnalysis.rms(sounding.left), 0.01)

        for note in [48, 55, 60, 64, 67] { engine.noteOff(note) }
        let tail = SignalAnalysis.render(engine, seconds: 20)
        let lastSecond = Array(tail.left.suffix(48_000)) + Array(tail.right.suffix(48_000))
        XCTAssertLessThan(SignalAnalysis.peak(lastSecond), 1e-5, "reverb and echoes must die away")
        XCTAssertEqual(engine.status.activeVoices, 0)
        XCTAssertTrue(tail.left.suffix(4_800).allSatisfy { $0 == 0 }, "a silent engine goes to sleep and outputs exact zeros")
    }

    func testExtremeParametersNeverProduceNaNOrInfinity() {
        var patches: [SynthPatch] = []
        for waveform in Waveform.allCases {
            for mode in FilterMode.allCases {
                var high = testPatch(waveform)
                high.osc2 = .init(waveform: .supersaw, octave: 2, detune: 50, pulseWidth: 0.95, spread: 1)
                high.oscMix = 0.5
                high.subLevel = 1
                high.filter = .init(mode: mode, cutoff: 20_000, resonance: 1, envelopeAmount: 8, keyTracking: 1, velocityAmount: 4, drive: 1)
                high.ampEnvelope = .init(attack: 0.001, decay: 0.005, sustain: 1, release: 0.005)
                high.filterEnvelope = .init(attack: 0.001, decay: 0.005, sustain: 0, release: 0.005)
                high.lfo = .init(shape: .triangle, rate: 20, pitchDepth: 100, cutoffDepth: 4)
                high.level = 1.5
                high.effects = .init(chorusMix: 1, delayTime: 0.02, delayFeedback: 0.95, delayMix: 1, reverbDecay: 12, reverbDamping: 0, reverbMix: 1)

                var low = high
                low.osc1.octave = -2
                low.osc1.pulseWidth = 0.05
                low.filter.cutoff = 20
                low.filter.envelopeAmount = -4
                low.effects.delayTime = 1.5
                low.effects.reverbDamping = 1
                patches.append(high)
                patches.append(low)
            }
        }
        // Out-of-range and non-finite values must be sanitized, not trusted.
        var hostile = testPatch(.sawtooth)
        hostile.filter.cutoff = .nan
        hostile.filter.resonance = 50
        hostile.osc1.detune = .infinity
        hostile.osc2.octave = 99
        hostile.lfo.rate = -3
        hostile.effects.delayFeedback = 7
        patches.append(hostile)

        let engine = SynthEngine(sampleRate: sampleRate, patch: patches[0], masterGain: 1.5)
        for (index, patch) in patches.enumerated() {
            engine.setPatch(patch)
            for note in [0, 21, 60, 108, 127] { engine.noteOn(note, velocity: index % 2 == 0 ? 1 : 0.01) }
            let block = SignalAnalysis.render(engine, seconds: 0.15, blockSize: 333)
            for note in [0, 21, 60, 108, 127] { engine.noteOff(note) }
            let all = block.left + block.right
            XCTAssertTrue(all.allSatisfy(\.isFinite), "patch \(index) produced NaN or infinity")
            XCTAssertLessThanOrEqual(SignalAnalysis.peak(all), 1.5, "patch \(index): the soft clipper bounds the output")
        }
    }

    func testVoiceStealingAtThePolyphonyLimit() {
        var patch = testPatch(.sine)
        patch.ampEnvelope.release = 2
        let engine = SynthEngine(sampleRate: sampleRate, patch: patch, masterGain: 1)
        for note in 60 ..< 68 { engine.noteOn(note, velocity: 0.8) }
        _ = SignalAnalysis.render(engine, seconds: 0.05)
        XCTAssertEqual(engine.status.activeVoices, SynthEngine.polyphony)
        XCTAssertEqual(engine.status.heldNotes, SynthNoteSet(60 ..< 68))

        // A ninth note takes over the oldest voice.
        engine.noteOn(68, velocity: 0.8)
        _ = SignalAnalysis.render(engine, seconds: 0.02)
        XCTAssertEqual(engine.status.activeVoices, SynthEngine.polyphony)
        XCTAssertEqual(engine.status.heldNotes, SynthNoteSet(61 ..< 69))

        // Release tails are stolen before held notes, even when they are younger.
        engine.noteOff(65)
        _ = SignalAnalysis.render(engine, seconds: 0.02)
        engine.noteOn(69, velocity: 0.8)
        _ = SignalAnalysis.render(engine, seconds: 0.02)
        XCTAssertEqual(engine.status.heldNotes, SynthNoteSet([61, 62, 63, 64, 66, 67, 68, 69]))
        XCTAssertFalse(engine.status.soundingNotes.contains(65))
    }

    func testStealingAVoiceDoesNotClick() {
        var patch = testPatch(.sine)
        patch.ampEnvelope = .init(attack: 0.01, decay: 0.1, sustain: 1, release: 2)
        patch.level = 0.25 // keep eight voices below the soft clipper's knee
        let engine = SynthEngine(sampleRate: sampleRate, patch: patch, masterGain: 1)
        for note in 48 ..< 56 { engine.noteOn(note, velocity: 1) }
        let steady = SignalAnalysis.render(engine, seconds: 0.5).left
        let steadyStep = largestStep(Array(steady[12_000...]))

        engine.noteOn(60, velocity: 1)
        let stealing = SignalAnalysis.render(engine, seconds: 0.05).left
        XCTAssertLessThan(largestStep(stealing), steadyStep * 1.5 + 0.002, "the stolen voice must fade, not cut")
    }

    func testRetriggeringANoteReusesItsVoice() {
        let engine = SynthEngine(sampleRate: sampleRate, patch: testPatch(.sawtooth), masterGain: 1)
        engine.noteOn(60, velocity: 0.5)
        _ = SignalAnalysis.render(engine, seconds: 0.05)
        engine.noteOn(60, velocity: 1)
        _ = SignalAnalysis.render(engine, seconds: 0.05)
        XCTAssertEqual(engine.status.activeVoices, 1)
    }

    func testMutedOutputStillFeedsTheVisualizers() {
        let engine = SynthEngine(sampleRate: sampleRate, patch: testPatch(.sawtooth), masterGain: 0)
        engine.noteOn(57, velocity: 1)
        let output = SignalAnalysis.render(engine, seconds: 0.3)
        XCTAssertTrue(output.left.allSatisfy { $0 == 0 }, "master gain 0 mutes the output")

        var recent = [Float](repeating: 0, count: 4_096)
        XCTAssertEqual(engine.copyRecentOutput(into: &recent), 4_096)
        XCTAssertGreaterThan(SignalAnalysis.rms(recent), 0.05, "the tap sits before the master gain")

        var scope = [Float](repeating: 0, count: 1_024)
        XCTAssertTrue(engine.fillOscilloscope(&scope))
        XCTAssertEqual(scope[0], 0, accuracy: 0.05, "the trace starts at a zero crossing")
        XCTAssertGreaterThan(scope[8], scope[0], "…on a rising edge")
    }

    func testPatchesAndStatusArePlainData() {
        // Copying these across threads must never retain, release or free anything.
        XCTAssertTrue(_isPOD(SynthPatch.self))
        XCTAssertTrue(_isPOD(SynthStatus.self))
        XCTAssertTrue(_isPOD(SynthNoteSet.self))
    }

    func testEveryPresetSoundsAndStaysWithinRange() {
        for preset in SynthPreset.all {
            let engine = SynthEngine(sampleRate: sampleRate, patch: preset.patch, masterGain: 1)
            for note in [48, 55, 60, 64] { engine.noteOn(note, velocity: 0.8) }
            let audio = SignalAnalysis.render(engine, seconds: 1.5)
            let rms = SignalAnalysis.rms(audio.left + audio.right)
            XCTAssertGreaterThan(rms, 0.02, "\(preset.name) should be clearly audible")
            XCTAssertLessThan(SignalAnalysis.peak(audio.left + audio.right), 1.0001, "\(preset.name)")
        }
    }

    func testSequencerPlaysThroughTheEngineAndStopsCleanly() {
        let engine = SynthEngine(sampleRate: sampleRate, patch: SynthPreset.pluck.patch, masterGain: 1)
        engine.startSequencer(seed: 3)
        let audio = SignalAnalysis.render(engine, seconds: 4)
        XCTAssertGreaterThan(SignalAnalysis.rms(audio.left), 0.01)
        let status = engine.status
        XCTAssertTrue(status.isSequencerPlaying)
        XCTAssertNotNil(status.chord)
        XCTAssertGreaterThan(status.sequencerStep, 16)

        engine.stopSequencer()
        _ = SignalAnalysis.render(engine, seconds: 1)
        XCTAssertFalse(engine.status.isSequencerPlaying)
        XCTAssertTrue(engine.status.heldNotes.isEmpty, "stopping releases every sequencer note")
    }

    func testControlFromAnotherThreadWhileRendering() {
        let engine = SynthEngine(sampleRate: sampleRate, patch: SynthPreset.supersawLead.patch, masterGain: 1)
        let done = expectation(description: "control thread finished")
        DispatchQueue.global().async {
            var random = SynthRandom(seed: 11)
            for i in 0 ..< 3_000 {
                let note = 40 + random.nextInt(below: 40)
                if i % 2 == 0 { engine.noteOn(note, velocity: 0.7) } else { engine.noteOff(note) }
                if i % 50 == 0 {
                    var patch = SynthPreset.all[random.nextInt(below: SynthPreset.all.count)].patch
                    patch.filter.cutoff = 100 + random.nextUnit() * 8_000
                    engine.setPatch(patch)
                }
                _ = engine.status
            }
            done.fulfill()
        }
        var finite = true
        let deadline = Date().addingTimeInterval(10)
        var rendered = 0
        repeat {
            let block = SignalAnalysis.render(engine, seconds: 0.1, blockSize: 256)
            finite = finite && block.left.allSatisfy(\.isFinite) && block.right.allSatisfy(\.isFinite)
            rendered += 1
        } while rendered < 20 && Date() < deadline
        wait(for: [done], timeout: 10)
        XCTAssertTrue(finite)
        engine.releaseAllNotes()
        _ = SignalAnalysis.render(engine, seconds: 1)
        XCTAssertTrue(engine.status.heldNotes.isEmpty)
    }

    func testMeasuresItsOwnLoad() {
        let engine = SynthEngine(sampleRate: sampleRate, patch: SynthPreset.warmPad.patch, masterGain: 1)
        for note in [48, 52, 55, 59, 62, 64, 67, 71] { engine.noteOn(note) }
        _ = SignalAnalysis.render(engine, seconds: 1)
        let load = engine.status.cpuLoad
        XCTAssertGreaterThan(load, 0)
        XCTAssertLessThan(load, 1, "eight voices with every effect must render faster than real time")
    }

    private func largestStep(_ samples: [Float]) -> Float {
        var largest: Float = 0
        for i in 1 ..< samples.count { largest = max(largest, abs(samples[i] - samples[i - 1])) }
        return largest
    }
}
