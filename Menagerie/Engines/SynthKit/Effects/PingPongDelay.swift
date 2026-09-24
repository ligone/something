import Foundation

/// A stereo ping-pong echo.
///
/// The mono input enters the left line; the left line feeds the right and the right feeds back
/// into the left, so echoes bounce between the speakers, each one `feedback` times quieter. The
/// feedback path is band-limited (repeats darken like tape and never build up bass) and softly
/// saturated so even maximum feedback stays bounded. Delay-time changes glide, which bends the
/// pitch of the repeats like a tape machine instead of clicking.
final class PingPongDelay {
    private var leftLine: SynthDelayLine
    private var rightLine: SynthDelayLine
    private let sampleRate: Float
    private let maxDelay: Float
    private let glide: Float
    private let lowPassCoefficient: Float
    private let highPassCoefficient: Float
    private var delaySamples: Float
    private var lowPass: Float = 0
    private var highPassState: Float = 0
    private var feedback: Float = 0
    private var mix: Float = 0

    /// - Parameter maximumTime: Longest delay in seconds.
    init(sampleRate: Double, maximumTime: Double = 1.6) {
        let length = Int(sampleRate * maximumTime) + 8
        leftLine = SynthDelayLine(minimumLength: length)
        rightLine = SynthDelayLine(minimumLength: length)
        self.sampleRate = Float(sampleRate)
        maxDelay = Float(sampleRate * maximumTime)
        glide = SynthMath.smoothingCoefficient(time: 0.08, rate: sampleRate)
        lowPassCoefficient = SynthMath.onePoleCoefficient(cutoff: 4_200, sampleRate: sampleRate)
        highPassCoefficient = SynthMath.onePoleCoefficient(cutoff: 110, sampleRate: sampleRate)
        delaySamples = Float(sampleRate * 0.35)
    }

    deinit {
        leftLine.deallocate()
        rightLine.deallocate()
    }

    /// Clears both lines and the tone filters.
    func reset() {
        leftLine.clear()
        rightLine.clear()
        lowPass = 0
        highPassState = 0
    }

    /// Processes a block in place.
    ///
    /// - Parameters:
    ///   - time: Echo spacing in seconds (glides to the new value).
    ///   - feedback: 0 … 0.95.
    ///   - mix: Wet level, 0 … 1.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int, time: Float, feedback targetFeedback: Float, mix targetMix: Float) {
        guard count > 0 else { return }
        var leftLine = self.leftLine
        var rightLine = self.rightLine
        var delay = delaySamples
        var lp = lowPass
        var hp = highPassState
        var fb = feedback
        var mix = self.mix
        let targetDelay = min(max(time * sampleRate, 2), maxDelay)
        let glide = self.glide
        let lpCoefficient = lowPassCoefficient
        let hpCoefficient = highPassCoefficient
        let inverseCount = 1 / Float(count)
        let fbStep = (min(max(targetFeedback, 0), 0.95) - fb) * inverseCount
        let mixStep = (targetMix - mix) * inverseCount
        // A vanishing offset keeps the recirculating tone filters out of the denormal range.
        let antiDenormal: Float = 1e-20

        for i in 0 ..< count {
            delay += (targetDelay - delay) * glide
            fb += fbStep
            mix += mixStep
            let echoLeft = leftLine.readCubic(delay)
            let echoRight = rightLine.readCubic(delay)
            let input = (left[i] + right[i]) * 0.5

            lp += (echoRight - lp) * lpCoefficient + antiDenormal
            hp += (lp - hp) * hpCoefficient
            let toned = lp - hp
            leftLine.write(input + 2 * SynthMath.softSaturate(0.5 * toned * fb))
            rightLine.write(echoLeft * fb)

            left[i] += echoLeft * mix
            right[i] += echoRight * mix
        }

        self.leftLine = leftLine
        self.rightLine = rightLine
        delaySamples = delay
        lowPass = lp
        highPassState = hp
        feedback = fb
        self.mix = mix
    }
}
