/// The outcome of a definite integral.
public struct IntegralResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Converged to the requested accuracy.
        case converged
        /// The evaluation budget ran out first, as it can for wildly
        /// oscillating integrands like `sin(1/x)`. The value is a best estimate.
        case approximate
        /// The integrand has a singularity that isn't integrable, like `1/x`
        /// at 0, so the integral has no finite value.
        case divergent
        /// The integrand is undefined on part of the interval, like `ln(x)`
        /// for x < 0.
        case undefined
    }

    public var value: Double
    /// An estimate of the absolute error.
    public var errorEstimate: Double
    public var status: Status
    /// How many times the integrand was evaluated.
    public var evaluations: Int

    public init(value: Double, errorEstimate: Double, status: Status, evaluations: Int) {
        self.value = value
        self.errorEstimate = errorEstimate
        self.status = status
        self.evaluations = evaluations
    }
}

/// Definite integrals by adaptive Simpson's rule.
///
/// The interval is split into panels, and each panel is bisected until
/// Simpson's rule on the halves agrees with Simpson's rule on the whole to
/// within its share of the tolerance. The difference between the two also
/// gives a free Richardson correction (`δ/15`) that raises the order of the
/// method.
///
/// Integrands don't have to be well behaved:
///
/// * Points where `f` is NaN or infinite are nudged a hair sideways, which
///   handles removable singularities (`sin(x)/x` at 0) and integrable
///   endpoint singularities (`ln(x)` at 0).
/// * Recursion depth and the number of evaluations are capped.
/// * If the pieces that hit the depth limit still carry real area, the
///   integrand has a non-integrable singularity and the result is
///   ``IntegralResult/Status-swift.enum/divergent``.
public enum Integrator {
    public static func adaptiveSimpson(
        _ f: (Double) -> Double,
        from lower: Double,
        to upper: Double,
        tolerance: Double = 1e-10,
        panels: Int = 64,
        maxDepth: Int = 40,
        maxEvaluations: Int = 100_000
    ) -> IntegralResult {
        guard lower.isFinite, upper.isFinite else {
            return IntegralResult(value: .nan, errorEstimate: .nan, status: .undefined, evaluations: 0)
        }
        if lower == upper {
            return IntegralResult(value: 0, errorEstimate: 0, status: .converged, evaluations: 0)
        }
        if lower > upper {
            var reversed = adaptiveSimpson(
                f, from: upper, to: lower, tolerance: tolerance,
                panels: panels, maxDepth: maxDepth, maxEvaluations: maxEvaluations
            )
            reversed.value = -reversed.value
            return reversed
        }

        var integration = Integration(lower: lower, upper: upper, maxDepth: maxDepth, maxEvaluations: maxEvaluations)
        let value = integration.run(f, panels: max(1, panels), tolerance: tolerance)

        let status: IntegralResult.Status
        if integration.undefined {
            return IntegralResult(value: .nan, errorEstimate: .nan, status: .undefined, evaluations: integration.evaluations)
        } else if !value.isFinite || integration.infinite || integration.depthLimitedArea > 1e-4 * max(1, abs(value)) {
            status = .divergent
        } else if integration.budgetExceeded {
            status = .approximate
        } else {
            status = .converged
        }
        return IntegralResult(
            value: value,
            errorEstimate: integration.errorEstimate,
            status: status,
            evaluations: integration.evaluations
        )
    }
}

/// The bookkeeping for one adaptive Simpson integration.
private struct Integration {
    let lower: Double
    let upper: Double
    let maxDepth: Int
    let maxEvaluations: Int

    var evaluations = 0
    var errorEstimate = 0.0
    /// The absolute area of the pieces that couldn't be refined further.
    var depthLimitedArea = 0.0
    var budgetExceeded = false
    var undefined = false
    var infinite = false

    init(lower: Double, upper: Double, maxDepth: Int, maxEvaluations: Int) {
        self.lower = lower
        self.upper = upper
        self.maxDepth = maxDepth
        self.maxEvaluations = maxEvaluations
    }

    mutating func run(_ f: (Double) -> Double, panels: Int, tolerance: Double) -> Double {
        let width = (upper - lower) / Double(panels)
        var edges: [Double] = []
        var edgeValues: [Double] = []
        var middles: [Double] = []
        for panel in 0...panels {
            let x = panel == panels ? upper : lower + Double(panel) * width
            edges.append(x)
            edgeValues.append(sample(f, x))
        }
        for panel in 0..<panels {
            middles.append(sample(f, 0.5 * (edges[panel] + edges[panel + 1])))
        }

        // Scale the tolerance to the size of the integrand.
        var roughArea = 0.0
        for panel in 0..<panels {
            let h = edges[panel + 1] - edges[panel]
            roughArea += h / 6 * (abs(edgeValues[panel]) + 4 * abs(middles[panel]) + abs(edgeValues[panel + 1]))
        }
        let panelTolerance = max(tolerance * roughArea, 1e-300) / Double(panels)

        var total = 0.0
        for panel in 0..<panels {
            let a = edges[panel]
            let b = edges[panel + 1]
            let fa = edgeValues[panel]
            let fm = middles[panel]
            let fb = edgeValues[panel + 1]
            let whole = (b - a) / 6 * (fa + 4 * fm + fb)
            total += refine(f, a, b, fa, fm, fb, whole, panelTolerance, maxDepth)
        }
        return total
    }

    /// Simpson's rule on `[a, b]`, refined until the halves agree with the
    /// whole.
    mutating func refine(
        _ f: (Double) -> Double,
        _ a: Double, _ b: Double,
        _ fa: Double, _ fm: Double, _ fb: Double,
        _ whole: Double, _ tolerance: Double, _ depth: Int
    ) -> Double {
        let m = 0.5 * (a + b)
        let leftMiddle = 0.5 * (a + m)
        let rightMiddle = 0.5 * (m + b)
        let fLeft = sample(f, leftMiddle)
        let fRight = sample(f, rightMiddle)
        let left = (m - a) / 6 * (fa + 4 * fLeft + fm)
        let right = (b - m) / 6 * (fm + 4 * fRight + fb)
        let delta = left + right - whole

        if depth <= 0 || leftMiddle <= a || rightMiddle >= b {
            depthLimitedArea += abs(left + right)
            errorEstimate += abs(delta)
            return left + right + delta / 15
        }
        if evaluations >= maxEvaluations {
            budgetExceeded = true
            errorEstimate += abs(delta)
            return left + right + delta / 15
        }
        if abs(delta) <= 15 * tolerance {
            errorEstimate += abs(delta) / 15
            return left + right + delta / 15
        }
        return refine(f, a, m, fa, fLeft, fm, left, tolerance / 2, depth - 1)
            + refine(f, m, b, fm, fRight, fb, right, tolerance / 2, depth - 1)
    }

    /// `f(x)`, looking a hair to either side when `f` is undefined at `x`.
    mutating func sample(_ f: (Double) -> Double, _ x: Double) -> Double {
        evaluations += 1
        let y = f(x)
        if y.isFinite { return y }

        let nudge = max(1e-9 * (upper - lower), 4 * x.ulp)
        var neighbors: [Double] = []
        if x - nudge >= lower { neighbors.append(f(x - nudge)) }
        if x + nudge <= upper { neighbors.append(f(x + nudge)) }
        evaluations += neighbors.count

        let finite = neighbors.filter(\.isFinite)
        if !finite.isEmpty {
            return finite.reduce(0, +) / Double(finite.count)
        }
        // Undefined here and next door: either f is undefined on a stretch
        // of the interval, or it blows up.
        if y.isNaN || neighbors.contains(where: \.isNaN) {
            undefined = true
        } else {
            infinite = true
        }
        return 0
    }
}
