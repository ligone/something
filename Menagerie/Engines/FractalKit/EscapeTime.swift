import Foundation

/// A CPU reference implementation of the escape-time algorithm, matching what
/// the GPU shader computes. The app renders on the GPU; this version backs
/// the tests, the pointer read-out and landmark verification.
public enum EscapeTime {
    /// A large bailout radius makes the smooth iteration count accurate.
    public static let bailoutRadius: Double = 256

    /// The continuous ("smooth") escape count for a starting point `z` and
    /// parameter `c`, or `nil` if the orbit is still bounded after
    /// `maxIterations`, i.e. the point is presumed to be in the set.
    ///
    /// The fractional part comes from how far past the bailout radius the
    /// orbit landed: `n + 1 − log₂(log |z|)`. It removes the banding of
    /// integer counts.
    public static func smoothCount(
        zRe: Double, zIm: Double,
        cRe: Double, cIm: Double,
        maxIterations: Int
    ) -> Double? {
        var x = zRe
        var y = zIm
        let bailout2 = bailoutRadius * bailoutRadius
        for n in 0..<maxIterations {
            let x2 = x * x
            let y2 = y * y
            if x2 + y2 > bailout2 {
                let logModulus = 0.5 * log(x2 + y2)
                return Double(n) + 1 - log2(logModulus / log(2))
            }
            y = 2 * x * y + cIm
            x = x2 - y2 + cRe
        }
        return nil
    }

    /// Smooth escape count of `c` in the Mandelbrot set.
    public static func mandelbrot(re: Double, im: Double, maxIterations: Int) -> Double? {
        if isInMainCardioidOrPeriod2Bulb(re: re, im: im) { return nil }
        return smoothCount(zRe: 0, zIm: 0, cRe: re, cIm: im, maxIterations: maxIterations)
    }

    /// Smooth escape count of `z` in the Julia set for parameter `c`.
    public static func julia(re: Double, im: Double, cRe: Double, cIm: Double, maxIterations: Int) -> Double? {
        smoothCount(zRe: re, zIm: im, cRe: cRe, cIm: cIm, maxIterations: maxIterations)
    }

    /// Escape count for either kind of fractal.
    public static func count(for kind: FractalKind, re: Double, im: Double, maxIterations: Int) -> Double? {
        switch kind {
        case .mandelbrot:
            return mandelbrot(re: re, im: im, maxIterations: maxIterations)
        case let .julia(cRe, cIm):
            return julia(re: re, im: im, cRe: cRe, cIm: cIm, maxIterations: maxIterations)
        }
    }

    /// Closed-form membership test for the two largest components of the
    /// Mandelbrot set, which would otherwise burn the full iteration budget.
    public static func isInMainCardioidOrPeriod2Bulb(re: Double, im: Double) -> Bool {
        let y2 = im * im
        let q = (re - 0.25) * (re - 0.25) + y2
        if q * (q + (re - 0.25)) <= 0.25 * y2 { return true }
        return (re + 1) * (re + 1) + y2 <= 1.0 / 16
    }

    /// A sensible iteration budget for a view: deeper views need longer
    /// orbits to resolve the boundary.
    public static func iterationBudget(magnification: Double, detail: Double = 1) -> Int {
        let depth = log10(max(magnification, 1))
        let base = 220 + 190 * depth + 14 * depth * depth
        return Int(min(max(base * detail, 64), 12_000))
    }
}
