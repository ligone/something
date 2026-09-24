import Foundation

/// Turns recent audio into smoothed, log-spaced band levels with peak hold, ready to draw.
///
/// Each call windows the newest `fftSize` samples with a Hann window, transforms them, and maps
/// the bins onto `bandCount` bands spaced evenly in log frequency. Bands narrower than a bin (the
/// low end) interpolate between neighboring bins. Levels are in decibels relative to a full-scale
/// sine, tilted by `tiltPerOctave` around 1 kHz (music falls off at high frequencies; the tilt
/// makes it read as balanced), then normalized to 0 … 1 above `floorDecibels`. Rises are fast and
/// falls slow, and each band keeps a peak marker that holds briefly and then drifts down.
///
/// Not thread-safe: use one analyzer per drawing thread (typically the main thread).
public final class SynthSpectrumAnalyzer {
    public let fftSize: Int
    public let bandCount: Int
    public let sampleRate: Double
    public let minimumFrequency: Double
    public let maximumFrequency: Double
    /// Level shown as 0.
    public var floorDecibels: Float = -78
    /// Display tilt in dB per octave around 1 kHz.
    public var tiltPerOctave: Float = 3

    /// Smoothed band levels, 0 … 1.
    public private(set) var levels: [Float]
    /// Peak-hold markers, 0 … 1.
    public private(set) var peaks: [Float]

    private let fft: SynthFFT
    private var window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var power: [Float]
    private var targets: [Float]
    private var holdTimes: [Double]
    private let bandLowBin: [Int]
    private let bandHighBin: [Int]
    private let bandCenterBin: [Float]
    private let bandTilt: [Float]
    private let normalization: Float

    public init(fftSize: Int = 4_096, bandCount: Int = 72, sampleRate: Double, minimumFrequency: Double = 30, maximumFrequency: Double = 16_000) {
        precondition(bandCount > 0)
        self.fftSize = fftSize
        self.bandCount = bandCount
        self.sampleRate = sampleRate
        self.minimumFrequency = minimumFrequency
        let top = min(maximumFrequency, sampleRate * 0.49)
        self.maximumFrequency = top
        fft = SynthFFT(size: fftSize)
        window = (0 ..< fftSize).map { i in
            Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(fftSize)))
        }
        real = Array(repeating: 0, count: fftSize)
        imag = Array(repeating: 0, count: fftSize)
        power = Array(repeating: 0, count: fftSize / 2 + 1)
        targets = Array(repeating: 0, count: bandCount)
        levels = Array(repeating: 0, count: bandCount)
        peaks = Array(repeating: 0, count: bandCount)
        holdTimes = Array(repeating: 0, count: bandCount)

        let binWidth = sampleRate / Double(fftSize)
        let ratio = top / minimumFrequency
        var lows: [Int] = []
        var highs: [Int] = []
        var centers: [Float] = []
        var tilts: [Float] = []
        for band in 0 ..< bandCount {
            let lowEdge = minimumFrequency * pow(ratio, Double(band) / Double(bandCount))
            let highEdge = minimumFrequency * pow(ratio, Double(band + 1) / Double(bandCount))
            let center = (lowEdge * highEdge).squareRoot()
            lows.append(Int((lowEdge / binWidth).rounded(.up)))
            highs.append(min(Int((highEdge / binWidth).rounded(.down)), fftSize / 2))
            centers.append(Float(center / binWidth))
            tilts.append(Float(log2(center / 1_000)))
        }
        bandLowBin = lows
        bandHighBin = highs
        bandCenterBin = centers
        bandTilt = tilts
        // A full-scale sine through a Hann window peaks at N/4 in its bin.
        normalization = 4 / Float(fftSize)
    }

    /// Center frequency of `band` in hertz.
    public func frequency(ofBand band: Int) -> Double {
        let ratio = maximumFrequency / minimumFrequency
        return minimumFrequency * pow(ratio, (Double(band) + 0.5) / Double(bandCount))
    }

    /// Clears levels and peaks.
    public func reset() {
        for i in 0 ..< bandCount {
            levels[i] = 0
            peaks[i] = 0
            holdTimes[i] = 0
        }
    }

    /// Analyzes the newest `fftSize` samples of `samples` (a shorter buffer is zero-padded at the
    /// front) and advances smoothing by `deltaTime` seconds.
    public func analyze(_ samples: UnsafeBufferPointer<Float>, deltaTime: Double) {
        let available = min(samples.count, fftSize)
        let offset = fftSize - available
        let source = samples.count - available
        for i in 0 ..< fftSize {
            real[i] = i < offset ? 0 : samples[source + i - offset] * window[i]
            imag[i] = 0
        }
        fft.forward(real: &real, imag: &imag)
        for k in 0 ... fftSize / 2 {
            power[k] = real[k] * real[k] + imag[k] * imag[k]
        }
        computeBandTargets()
        smooth(deltaTime: deltaTime)
    }

    /// Analyzes a Swift array (see `analyze(_:deltaTime:)`).
    public func analyze(_ samples: [Float], deltaTime: Double) {
        samples.withUnsafeBufferPointer { analyze($0, deltaTime: deltaTime) }
    }

    /// Lets levels fall when no new audio is available.
    public func decay(deltaTime: Double) {
        for band in 0 ..< bandCount { targets[band] = 0 }
        smooth(deltaTime: deltaTime)
    }

    // MARK: - Private

    private func computeBandTargets() {
        let top = fftSize / 2
        for band in 0 ..< bandCount {
            var bandPower: Float
            if bandHighBin[band] >= bandLowBin[band] {
                bandPower = 0
                for k in bandLowBin[band] ... bandHighBin[band] { bandPower = max(bandPower, power[k]) }
            } else {
                // Narrower than one bin: interpolate the magnitude at the band center.
                let position = bandCenterBin[band]
                let k = min(Int(position), top - 1)
                let t = position - Float(k)
                let magnitude = power[k].squareRoot() * (1 - t) + power[k + 1].squareRoot() * t
                bandPower = magnitude * magnitude
            }
            let amplitude = bandPower.squareRoot() * normalization
            let decibels = 20 * log10(max(amplitude, 1e-9)) + tiltPerOctave * bandTilt[band]
            targets[band] = min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
        }
    }

    private func smooth(deltaTime: Double) {
        let dt = max(deltaTime, 0)
        let rise = Float(1 - exp(-dt / 0.012))
        let fall = Float(1 - exp(-dt / 0.22))
        let peakFall = Float(dt * 0.45)
        for band in 0 ..< bandCount {
            let target = targets[band]
            let level = levels[band]
            let updated = level + (target - level) * (target > level ? rise : fall)
            levels[band] = updated
            if updated >= peaks[band] {
                peaks[band] = updated
                holdTimes[band] = 0.7
            } else if holdTimes[band] > 0 {
                holdTimes[band] -= dt
            } else {
                peaks[band] = max(peaks[band] - peakFall, updated)
            }
        }
    }
}
