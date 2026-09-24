import Foundation

/// A lush stereo reverb built from an eight-line feedback delay network (FDN).
///
/// The input passes through a pre-delay and four series all-pass diffusers (after Dattorro) that
/// smear transients into a dense wash. It then feeds eight delay lines of mutually prime lengths
/// whose outputs are mixed by an 8×8 Hadamard matrix and fed back. The matrix is orthogonal, so the
/// network is lossless until each line's gain sets the decay time. A one-pole low-pass in every
/// loop makes high frequencies die first, as they do in real rooms, and slowly drifting read
/// positions stop the tail from ringing metallically.
final class FDNReverb {
    private static let lineCount = 8
    private static let diffuserCount = 4
    /// Line lengths in milliseconds before rounding to primes.
    private static let lineMilliseconds: [Double] = [37.7, 43.1, 49.3, 56.9, 63.7, 71.3, 79.9, 89.3]
    private static let diffuserMilliseconds: [Double] = [4.77, 3.60, 12.73, 9.31]
    private static let modulationRates: [Double] = [0.31, 0.43, 0.53, 0.61, 0.37, 0.47, 0.59, 0.71]

    private let sampleRate: Double
    private let lines: UnsafeMutablePointer<SynthDelayLine>
    private let diffusers: UnsafeMutablePointer<SynthDelayLine>
    private let diffuserDelays: UnsafeMutablePointer<Int>
    private let diffuserGains: SIMD4<Float>
    private var predelay: SynthDelayLine
    private let predelaySamples: Int

    private let baseDelays: SIMD8<Float>
    private let modulationDepth: Float
    private var modulationCos: SIMD8<Float>
    private var modulationSin: SIMD8<Float>
    private let rotationCos: SIMD8<Float>
    private let rotationSin: SIMD8<Float>

    private var dampingState = SIMD8<Float>(repeating: 0)
    private var decayGains = SIMD8<Float>(repeating: 0)
    private var dampingCoefficient: Float = 0.5
    private var outputGain: Float = 0.3
    private var configuredDecay: Float = -1
    private var configuredDamping: Float = -1
    private var mix: Float = 0

    // Orthogonal sign patterns (rows of a Hadamard matrix) for injection and the two outputs.
    private let inputSigns = SIMD8<Float>(1, -1, -1, 1, 1, -1, -1, 1)
    private let leftSigns = SIMD8<Float>(1, -1, 1, -1, 1, -1, 1, -1)
    private let rightSigns = SIMD8<Float>(1, 1, -1, -1, 1, 1, -1, -1)

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let perMillisecond = sampleRate / 1_000
        modulationDepth = Float(0.35 * perMillisecond)

        var delays = SIMD8<Float>(repeating: 0)
        var used = Set<Int>()
        lines = .allocate(capacity: Self.lineCount)
        for i in 0 ..< Self.lineCount {
            var length = Self.nextPrime(Int(Self.lineMilliseconds[i] * perMillisecond))
            while used.contains(length) { length = Self.nextPrime(length + 1) }
            used.insert(length)
            delays[i] = Float(length)
            let capacity = length + Int(modulationDepth) + 8
            (lines + i).initialize(to: SynthDelayLine(minimumLength: capacity))
        }
        baseDelays = delays

        diffusers = .allocate(capacity: Self.diffuserCount)
        diffuserDelays = .allocate(capacity: Self.diffuserCount)
        diffuserGains = SIMD4<Float>(0.75, 0.75, 0.625, 0.625)
        for i in 0 ..< Self.diffuserCount {
            let length = max(Self.nextPrime(Int(Self.diffuserMilliseconds[i] * perMillisecond)), 2)
            diffuserDelays[i] = length
            (diffusers + i).initialize(to: SynthDelayLine(minimumLength: length + 2))
        }

        predelaySamples = max(Int(0.014 * sampleRate), 1)
        predelay = SynthDelayLine(minimumLength: predelaySamples + 2)

        var cosines = SIMD8<Float>(repeating: 0)
        var sines = SIMD8<Float>(repeating: 0)
        var rotationCos = SIMD8<Float>(repeating: 0)
        var rotationSin = SIMD8<Float>(repeating: 0)
        for i in 0 ..< Self.lineCount {
            let start = Double(i) * 2 * Double.pi / Double(Self.lineCount)
            cosines[i] = Float(cos(start))
            sines[i] = Float(sin(start))
            let step = 2 * Double.pi * Self.modulationRates[i] / sampleRate
            rotationCos[i] = Float(cos(step))
            rotationSin[i] = Float(sin(step))
        }
        modulationCos = cosines
        modulationSin = sines
        self.rotationCos = rotationCos
        self.rotationSin = rotationSin
    }

    deinit {
        for i in 0 ..< Self.lineCount { lines[i].deallocate() }
        lines.deinitialize(count: Self.lineCount)
        lines.deallocate()
        for i in 0 ..< Self.diffuserCount { diffusers[i].deallocate() }
        diffusers.deinitialize(count: Self.diffuserCount)
        diffusers.deallocate()
        diffuserDelays.deallocate()
        predelay.deallocate()
    }

    /// Clears the tail.
    func reset() {
        for i in 0 ..< Self.lineCount { lines[i].clear() }
        for i in 0 ..< Self.diffuserCount { diffusers[i].clear() }
        predelay.clear()
        dampingState = SIMD8<Float>(repeating: 0)
    }

    /// Processes a block in place.
    ///
    /// - Parameters:
    ///   - decay: Time for the tail to fall by 60 dB, in seconds.
    ///   - damping: 0 (bright) … 1 (dark).
    ///   - mix: Wet level added to the dry signal, 0 … 1.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int, decay: Float, damping: Float, mix targetMix: Float) {
        guard count > 0 else { return }
        configure(decay: decay, damping: damping)

        var predelay = self.predelay
        var damp = dampingState
        var modCos = modulationCos
        var modSin = modulationSin
        var mix = self.mix
        let mixStep = (targetMix - mix) / Float(count)
        let rotCos = rotationCos
        let rotSin = rotationSin
        let base = baseDelays
        let depth = modulationDepth
        let gains = decayGains
        let dampCoefficient = dampingCoefficient
        let outGain = outputGain
        let predelayLength = predelaySamples
        let lines = self.lines
        let diffusers = self.diffusers
        let diffuserDelays = self.diffuserDelays
        let inSigns = inputSigns
        let lSigns = leftSigns
        let rSigns = rightSigns
        let normalization: Float = 1 / Float(8).squareRoot()
        let antiDenormal = SIMD8<Float>(repeating: 1e-20)
        let g0 = diffuserGains[0]
        let g1 = diffuserGains[1]
        let g2 = diffuserGains[2]
        let g3 = diffuserGains[3]

        for i in 0 ..< count {
            // Pre-delay, then four all-pass diffusers.
            let dryLeft = left[i]
            let dryRight = right[i]
            predelay.write((dryLeft + dryRight) * 0.5)
            // The tiny offset keeps the decaying all-pass states out of the denormal range.
            var x = predelay.read(predelayLength) + 1e-20
            x = Self.allpass(x, &diffusers[0], diffuserDelays[0], g0)
            x = Self.allpass(x, &diffusers[1], diffuserDelays[1], g1)
            x = Self.allpass(x, &diffusers[2], diffuserDelays[2], g2)
            x = Self.allpass(x, &diffusers[3], diffuserDelays[3], g3)

            // Read the eight lines at slowly drifting positions.
            let positions = base + depth * modSin
            var taps = SIMD8<Float>(repeating: 0)
            for line in 0 ..< 8 {
                taps[line] = lines[line].readLinear(positions[line])
            }

            // Damp, attenuate, mix orthogonally and write back with the new input.
            damp += (taps - damp) * dampCoefficient + antiDenormal
            let feedback = Self.hadamard(damp * gains) * normalization
            let injected = feedback + inSigns * (x * normalization)
            for line in 0 ..< 8 {
                lines[line].write(injected[line])
            }

            mix += mixStep
            let wetLeft = (taps * lSigns).sum() * outGain
            let wetRight = (taps * rSigns).sum() * outGain
            left[i] = dryLeft + wetLeft * mix
            right[i] = dryRight + wetRight * mix

            // Rotate the eight modulation phasors.
            let nextCos = modCos * rotCos - modSin * rotSin
            modSin = modCos * rotSin + modSin * rotCos
            modCos = nextCos
        }

        // Renormalize the phasors so rounding never lets them drift in amplitude.
        let magnitude = (modCos * modCos + modSin * modSin).squareRoot()
        modulationCos = modCos / magnitude
        modulationSin = modSin / magnitude
        self.predelay = predelay
        dampingState = damp
        self.mix = targetMix
    }

    // MARK: - Helpers

    /// Recomputes loop gains and damping when the parameters change.
    private func configure(decay: Float, damping: Float) {
        let decay = min(max(decay, 0.1), 30)
        let damping = min(max(damping, 0), 1)
        guard decay != configuredDecay || damping != configuredDamping else { return }
        configuredDecay = decay
        configuredDamping = damping
        var gains = SIMD8<Float>(repeating: 0)
        var meanSquare: Float = 0
        for i in 0 ..< Self.lineCount {
            // Each pass through line i must lose 60 dB · (length / RT60).
            let exponent = -3 * Double(baseDelays[i]) / (Double(decay) * sampleRate)
            let gain = Float(pow(10, exponent))
            gains[i] = gain
            meanSquare += gain * gain / Float(Self.lineCount)
        }
        decayGains = gains
        // Damping cutoff sweeps from 12 kHz (bright) to 1.5 kHz (dark) on a log scale.
        let cutoff = 12_000 * pow(1_500.0 / 12_000.0, Double(damping))
        dampingCoefficient = SynthMath.onePoleCoefficient(cutoff: cutoff, sampleRate: sampleRate)
        // Long tails accumulate more energy; take back half of that (in dB) so the mix control
        // means roughly the same thing at every decay time.
        outputGain = 0.55 * pow(max(1 - meanSquare, 1e-4), 0.25)
    }

    /// Schroeder all-pass: `y = −g·w + w[n−d]` with `w = x + g·w[n−d]`.
    @inline(__always)
    private static func allpass(_ x: Float, _ line: inout SynthDelayLine, _ delay: Int, _ g: Float) -> Float {
        let delayed = line.read(delay)
        let w = x + g * delayed
        line.write(w)
        return delayed - g * w
    }

    /// Unnormalized 8-point fast Walsh–Hadamard transform (three butterfly stages via SIMD
    /// even/odd shuffles). Every output is a ±1 combination of all eight inputs.
    @inline(__always)
    private static func hadamard(_ v: SIMD8<Float>) -> SIMD8<Float> {
        let a = SIMD8<Float>(lowHalf: v.evenHalf + v.oddHalf, highHalf: v.evenHalf - v.oddHalf)
        let b = SIMD8<Float>(lowHalf: a.evenHalf + a.oddHalf, highHalf: a.evenHalf - a.oddHalf)
        return SIMD8<Float>(lowHalf: b.evenHalf + b.oddHalf, highHalf: b.evenHalf - b.oddHalf)
    }

    private static func nextPrime(_ n: Int) -> Int {
        var candidate = max(n, 2)
        while !isPrime(candidate) { candidate += 1 }
        return candidate
    }

    private static func isPrime(_ n: Int) -> Bool {
        if n < 4 { return n >= 2 }
        if n % 2 == 0 { return false }
        var divisor = 3
        while divisor * divisor <= n {
            if n % divisor == 0 { return false }
            divisor += 2
        }
        return true
    }
}
