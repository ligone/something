/// A stereo chorus in the spirit of the Juno-60's.
///
/// One short delay line is read by two taps whose delay times a triangle LFO sweeps in opposite
/// directions. The slightly pitch-shifted copies beat against the dry signal and differ between
/// the ears, which turns a static tone into a wide, moving one.
final class StereoChorus {
    private var line: SynthDelayLine
    private let baseDelay: Float
    private let depth: Float
    private let phaseIncrement: Float
    private var phase: Float = 0
    private var mix: Float = 0

    init(sampleRate: Double) {
        line = SynthDelayLine(minimumLength: Int(sampleRate * 0.03) + 8)
        baseDelay = Float(sampleRate * 0.007)
        depth = Float(sampleRate * 0.0026)
        phaseIncrement = Float(0.6 / sampleRate)
    }

    deinit {
        line.deallocate()
    }

    /// Clears the delay line.
    func reset() {
        line.clear()
    }

    /// Processes a block in place; `targetMix` (0 … 1) is reached by the end of the block.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int, mix targetMix: Float) {
        guard count > 0 else { return }
        if targetMix < 1e-4 && mix < 1e-4 {
            // Bypassed: keep the line fed so switching on later does not replay stale audio.
            var line = self.line
            for i in 0 ..< count { line.write((left[i] + right[i]) * 0.5) }
            self.line = line
            mix = 0
            return
        }
        var line = self.line
        var phase = self.phase
        var mix = self.mix
        let mixStep = (targetMix - mix) / Float(count)
        let base = baseDelay
        let depth = self.depth
        let increment = phaseIncrement

        for i in 0 ..< count {
            let dryLeft = left[i]
            let dryRight = right[i]
            line.write((dryLeft + dryRight) * 0.5)
            let triangle = phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase
            let wetLeft = line.readCubic(base + depth * triangle)
            let wetRight = line.readCubic(base - depth * triangle)
            mix += mixStep
            let dryGain = 1 - 0.3 * mix
            let wetGain = 0.6 * mix
            left[i] = dryLeft * dryGain + wetLeft * wetGain
            right[i] = dryRight * dryGain + wetRight * wetGain
            phase += increment
            if phase >= 1 { phase -= 1 }
        }

        self.line = line
        self.phase = phase
        self.mix = targetMix
    }
}
