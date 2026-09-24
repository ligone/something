/// Numerical root finding.
///
/// ``roots(of:derivative:in:samples:limit:)`` scans an interval on a fine
/// grid and polishes every sign change with Brent's method, which combines
/// the guaranteed progress of bisection with the speed of secant and inverse
/// quadratic interpolation steps. Sign changes across poles and jumps are
/// recognized and discarded, and roots that only touch zero, such as the
/// double root of `x²`, are found as minima of `|f|`.
public enum RootFinder {
    /// A root of `f` between `lower` and `upper`, which must bracket a sign
    /// change. Returns nil when they don't, or when `f` is undefined at a
    /// point the method needs.
    ///
    /// - Parameter tolerance: The absolute accuracy wanted. The method also
    ///   stops at the limit of floating-point resolution, so 0 is allowed.
    public static func brent(
        _ f: (Double) -> Double,
        lower: Double,
        upper: Double,
        tolerance: Double = 0,
        maxIterations: Int = 200
    ) -> Double? {
        var a = lower
        var b = upper
        var fa = f(a)
        var fb = f(b)
        guard fa.isFinite, fb.isFinite else { return nil }
        if fa == 0 { return a }
        if fb == 0 { return b }
        guard (fa < 0) != (fb < 0) else { return nil }

        // `b` is the best estimate, `a` the previous one, and `c` keeps the
        // root bracketed together with `b`.
        var c = b
        var fc = fb
        var step = b - a
        var previousStep = step
        for _ in 0..<maxIterations {
            if (fb < 0) == (fc < 0) {
                c = a
                fc = fa
                step = b - a
                previousStep = step
            }
            if abs(fc) < abs(fb) {
                a = b; b = c; c = a
                fa = fb; fb = fc; fc = fa
            }
            let accuracy = 2 * Double.ulpOfOne * abs(b) + 0.5 * tolerance
            let midpoint = 0.5 * (c - b)
            if abs(midpoint) <= accuracy || fb == 0 { return b }

            if abs(previousStep) >= accuracy, abs(fa) > abs(fb) {
                // Try interpolation: secant when a == c, otherwise inverse
                // quadratic through a, b and c.
                let s = fb / fa
                var p: Double
                var q: Double
                if a == c {
                    p = 2 * midpoint * s
                    q = 1 - s
                } else {
                    let r = fb / fc
                    let t = fa / fc
                    p = s * (2 * midpoint * t * (t - r) - (b - a) * (r - 1))
                    q = (t - 1) * (r - 1) * (s - 1)
                }
                if p > 0 { q = -q }
                p = abs(p)
                let limit1 = 3 * midpoint * q - abs(accuracy * q)
                let limit2 = abs(previousStep * q)
                if 2 * p < min(limit1, limit2) {
                    previousStep = step
                    step = p / q
                } else {
                    step = midpoint
                    previousStep = step
                }
            } else {
                step = midpoint
                previousStep = step
            }

            a = b
            fa = fb
            b += abs(step) > accuracy ? step : (midpoint > 0 ? accuracy : -accuracy)
            fb = f(b)
            guard fb.isFinite else { return nil }
        }
        return b
    }

    /// The point in `[lower, upper]` where `g` is smallest, by golden-section
    /// search. `g` should be unimodal there.
    public static func minimum(
        of g: (Double) -> Double,
        lower: Double,
        upper: Double,
        iterations: Int = 90
    ) -> Double {
        let ratio = 0.6180339887498949
        var a = lower
        var b = upper
        var x1 = b - ratio * (b - a)
        var x2 = a + ratio * (b - a)
        var g1 = g(x1)
        var g2 = g(x2)
        for _ in 0..<iterations {
            if !(g1 > g2) {
                b = x2
                x2 = x1
                g2 = g1
                x1 = b - ratio * (b - a)
                g1 = g(x1)
            } else {
                a = x1
                x1 = x2
                g1 = g2
                x2 = a + ratio * (b - a)
                g2 = g(x2)
            }
            if b - a <= 4 * Double.ulpOfOne * max(abs(a), abs(b)) { break }
        }
        return 0.5 * (a + b)
    }

    /// Every root of `f` in `interval`, sorted.
    ///
    /// - Parameters:
    ///   - derivative: `f′`, if known. It pins down roots where `f` touches
    ///     zero without crossing it.
    ///   - samples: The resolution of the initial scan. Roots closer together
    ///     than one grid step may be missed.
    ///   - limit: The most roots to return, for functions like `sin(1/x)`.
    public static func roots(
        of f: (Double) -> Double,
        derivative: ((Double) -> Double)? = nil,
        in interval: ClosedRange<Double>,
        samples: Int = 2048,
        limit: Int = 100
    ) -> [Double] {
        let grid = SampleGrid(interval: interval, samples: samples, f: f)
        return roots(of: f, derivative: derivative, grid: grid, limit: limit)
    }

    static func roots(
        of f: (Double) -> Double,
        derivative: ((Double) -> Double)?,
        grid: SampleGrid,
        limit: Int
    ) -> [Double] {
        let xs = grid.xs
        let ys = grid.ys
        let tolerance = grid.tolerance
        var found: [Double] = []

        for i in 0..<(xs.count - 1) where found.count < limit {
            let y0 = ys[i]
            let y1 = ys[i + 1]
            if y0 == 0 {
                found.append(xs[i])
                continue
            }
            if y0.isFinite, y1.isFinite {
                guard y1 != 0, (y0 < 0) != (y1 < 0) else { continue }
                // A sign change: a root, unless it's a pole or a jump.
                let root = signChange(f, lower: xs[i], upper: xs[i + 1], tolerance: tolerance)
                let residual = abs(f(root))
                if residual <= 1e-5 * max(abs(y0), abs(y1)) {
                    found.append(root)
                }
            } else if y0.isFinite != y1.isFinite {
                // The edge of the domain, as for √x at 0: a root if f → 0 there.
                let finiteSide = y0.isFinite ? xs[i] : xs[i + 1]
                let edge = domainEdge(f, finite: finiteSide, undefined: y0.isFinite ? xs[i + 1] : xs[i])
                let value = f(edge)
                if value.isFinite, abs(value) <= 1e-5 * abs(y0.isFinite ? y0 : y1) {
                    found.append(edge)
                }
            }
        }
        if let last = ys.last, last == 0, let x = xs.last {
            found.append(x)
        }

        // Roots that touch zero without crossing it are minima of |f|.
        if ys.count >= 3 {
            for i in 1..<(ys.count - 1) where found.count < limit {
                let left = ys[i - 1]
                let middle = ys[i]
                let right = ys[i + 1]
                guard left.isFinite, middle.isFinite, right.isFinite, middle != 0,
                      (left < 0) == (middle < 0), (middle < 0) == (right < 0),
                      abs(middle) <= abs(left), abs(middle) <= abs(right),
                      abs(middle) < abs(left) || abs(middle) < abs(right) else { continue }
                let candidate = polishTouchingRoot(f, derivative: derivative, lower: xs[i - 1], upper: xs[i + 1], tolerance: tolerance)
                let value = f(candidate)
                if value.isFinite, abs(value) <= 1e-9 * max(abs(left), abs(right)) {
                    found.append(candidate)
                }
            }
        }

        return merged(found, within: grid.mergeDistance, limit: limit)
    }

    /// The minimum of `|f|` between two grid points, using a sign change of
    /// `f′` when there is one.
    static func polishTouchingRoot(
        _ f: (Double) -> Double,
        derivative: ((Double) -> Double)?,
        lower: Double,
        upper: Double,
        tolerance: Double
    ) -> Double {
        if let derivative, let critical = brent(derivative, lower: lower, upper: upper, tolerance: tolerance) {
            return critical
        }
        return minimum(of: { abs(f($0)) }, lower: lower, upper: upper)
    }

    /// Where `f` changes sign between `lower` and `upper`, by bisection. Unlike
    /// ``brent(_:lower:upper:tolerance:maxIterations:)`` it copes with a
    /// singularity inside the bracket: it returns the point where `f` stops
    /// being finite.
    static func bisection(_ f: (Double) -> Double, lower: Double, upper: Double) -> Double {
        var a = lower
        var b = upper
        let negativeAtA = f(a) < 0
        for _ in 0..<80 {
            let middle = 0.5 * (a + b)
            if middle == a || middle == b { break }
            let value = f(middle)
            if !value.isFinite { return middle }
            if value == 0 { return middle }
            if (value < 0) == negativeAtA { a = middle } else { b = middle }
        }
        return 0.5 * (a + b)
    }

    /// A sign change of `f` in a bracket: Brent's method when `f` is finite
    /// throughout, bisection otherwise.
    static func signChange(_ f: (Double) -> Double, lower: Double, upper: Double, tolerance: Double) -> Double {
        brent(f, lower: lower, upper: upper, tolerance: tolerance) ?? bisection(f, lower: lower, upper: upper)
    }

    /// The boundary between where `f` is defined and where it isn't, by
    /// bisection.
    static func domainEdge(_ f: (Double) -> Double, finite: Double, undefined: Double) -> Double {
        var good = finite
        var bad = undefined
        for _ in 0..<80 {
            let middle = 0.5 * (good + bad)
            if middle == good || middle == bad { break }
            if f(middle).isFinite { good = middle } else { bad = middle }
        }
        return good
    }

    /// Sorts values and merges runs closer than `distance`.
    static func merged(_ values: [Double], within distance: Double, limit: Int) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() {
            if let last = result.last, value - last <= distance { continue }
            result.append(value)
            if result.count == limit { break }
        }
        return result
    }
}

/// A function sampled on an evenly spaced grid.
struct SampleGrid {
    let xs: [Double]
    let ys: [Double]
    /// The median magnitude of the finite samples: a scale for "large".
    let typicalMagnitude: Double

    init(interval: ClosedRange<Double>, samples: Int, f: (Double) -> Double) {
        let count = max(8, samples)
        let lower = interval.lowerBound
        let span = interval.upperBound - lower
        let xs = (0...count).map { lower + span * Double($0) / Double(count) }
        self.init(xs: xs, ys: xs.map(f))
    }

    init(xs: [Double], ys: [Double]) {
        self.xs = xs
        self.ys = ys
        let magnitudes = ys.filter(\.isFinite).map(abs).sorted()
        if let largest = magnitudes.last {
            let median = magnitudes[magnitudes.count / 2]
            typicalMagnitude = median > 0 ? median : largest
        } else {
            typicalMagnitude = 1
        }
    }

    var span: Double { (xs.last ?? 0) - (xs.first ?? 0) }

    /// The absolute accuracy to polish roots to.
    var tolerance: Double { 1e-12 * span }

    /// Features closer than this are one feature.
    var mergeDistance: Double { 1e-7 * span }
}
