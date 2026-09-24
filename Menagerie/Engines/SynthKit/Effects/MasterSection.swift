import Foundation

/// A one-pole, one-zero high-pass that removes DC offset (about 8 Hz corner).
struct DCBlocker {
    private var previousInput: Float = 0
    private var previousOutput: Float = 0
    private let pole: Float

    init(sampleRate: Double) {
        pole = Float(1 - 2 * Double.pi * 8 / sampleRate)
    }

    mutating func reset() {
        previousInput = 0
        previousOutput = 0
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        var y = x - previousInput + pole * previousOutput
        // Flush the decaying state to zero before it becomes denormal.
        if abs(y) < 1e-24 { y = 0 }
        previousInput = x
        previousOutput = y
        return y
    }
}

/// The master saturator: perfectly clean below the knee, then a `tanh` curve that approaches
/// full scale smoothly (the join is continuous in value and slope), so peaks round off instead of
/// clipping and the output can never exceed ±1.
enum SoftClipper {
    /// Level below which the signal passes untouched.
    static var knee: Float { 0.6 }

    @inline(__always)
    static func process(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > knee else { return x }
        let headroom = 1 - knee
        let shaped = knee + headroom * tanh((magnitude - knee) / headroom)
        return x < 0 ? -shaped : shaped
    }
}
