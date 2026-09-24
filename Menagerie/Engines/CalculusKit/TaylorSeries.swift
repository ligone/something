/// The Taylor expansion of a function around a point:
/// `f(x) ≈ Σ cₖ(x − x₀)ᵏ` with `cₖ = f⁽ᵏ⁾(x₀)/k!`.
///
/// Coefficients come from automatic differentiation in truncated power
/// series arithmetic, which is exact up to rounding at any order and costs
/// O(n²) per operation, where repeated symbolic differentiation would make
/// expressions like `tan(x)` grow explosively.
public struct TaylorSeries: Equatable, Sendable {
    /// The expansion point, x₀.
    public let center: Double
    /// `coefficients[k]` is `f⁽ᵏ⁾(x₀)/k!`. NaN where the derivative doesn't
    /// exist, as for `√x` at 0.
    public let coefficients: [Double]

    public init(center: Double, coefficients: [Double]) {
        self.center = center
        self.coefficients = coefficients
    }

    /// The expansion of `expression` around `center`, through `order`.
    public init(_ expression: MathExpr, at center: Double, order: Int) {
        let count = max(0, order) + 1
        self.center = center
        // Simplifying first turns exponents like 1/3 into exact numbers, so
        // odd roots of negative numbers stay real.
        let canonical = MathSimplifier.simplify(expression)
        self.coefficients = PowerSeries.evaluate(canonical, at: center, count: count).c
    }

    /// The highest power available.
    public var order: Int { coefficients.count - 1 }

    /// The k-th derivative at the center, `k!·cₖ`.
    public func derivative(_ k: Int) -> Double {
        guard coefficients.indices.contains(k) else { return .nan }
        return coefficients[k] * TaylorSeries.factorial(k)
    }

    /// True when every coefficient through `order` exists.
    public func isDefined(through order: Int) -> Bool {
        coefficients.prefix(max(0, order) + 1).allSatisfy(\.isFinite)
    }

    /// The Taylor polynomial of the given order at `x`, by Horner's rule.
    public func evaluate(at x: Double, order: Int? = nil) -> Double {
        let last = min(order ?? self.order, self.order)
        guard last >= 0 else { return 0 }
        let t = x - center
        var result = coefficients[last]
        for k in stride(from: last - 1, through: 0, by: -1) {
            result = result * t + coefficients[k]
        }
        return result
    }

    /// The polynomial written out, lowest power first: `x − x³/6 + x⁵/120`,
    /// or `0.8415 + 0.5403(x − 1) − 0.4207(x − 1)²`.
    ///
    /// Coefficients whose derivatives `k!·cₖ` are simple fractions print
    /// exactly; others are rounded to `significantDigits`.
    public func polynomialDescription(order: Int? = nil, significantDigits: Int = 4) -> String {
        let last = min(order ?? self.order, self.order)
        guard last >= 0 else { return "0" }
        guard isDefined(through: last) else { return "undefined" }

        let largest = coefficients.prefix(last + 1).map(abs).max() ?? 0
        var terms: [(negative: Bool, text: String)] = []
        for k in 0...last {
            let coefficient = coefficients[k]
            guard abs(coefficient) > 1e-13 * largest, coefficient != 0 else { continue }
            terms.append(term(k, coefficient, significantDigits: significantDigits))
        }
        guard let first = terms.first else { return "0" }

        var text = first.negative ? "−" + first.text : first.text
        for term in terms.dropFirst() {
            text += term.negative ? " − " : " + "
            text += term.text
        }
        return text
    }

    // MARK: Helpers

    /// One term, `cₖ(x − x₀)ᵏ`, as its sign and the text of its magnitude.
    private func term(_ k: Int, _ coefficient: Double, significantDigits: Int) -> (negative: Bool, text: String) {
        var power = ""
        if k > 0 {
            if center == 0 {
                power = "x"
            } else {
                let shift = MathPrinter.decimal(abs(center), significantDigits: significantDigits)
                power = center > 0 ? "(x − \(shift))" : "(x + \(shift))"
            }
            if k > 1 { power += MathPrinter.superscript(k) }
        }

        // Exact when k!·cₖ is a simple fraction, as it is for most
        // expansions around 0: sin gives 1/k!, tan gives 2/15 and 17/315.
        let factorialValue = TaylorSeries.factorial(k)
        if k <= 20,
           let fraction = MathNumber.approximating(coefficient * factorialValue, maxDenominator: 100, tolerance: 1e-9)?.fraction,
           let denominator = MathNumber.multiply(fraction.denominator, Int(factorialValue)) {
            let exact = MathNumber(fraction.numerator, denominator)
            if let (p, q) = exact.fraction {
                let numerator = p.magnitude
                var text: String
                if power.isEmpty {
                    text = "\(numerator)"
                } else {
                    text = numerator == 1 ? power : "\(numerator)\(power)"
                }
                if q != 1 { text += "/\(q)" }
                return (p < 0, text)
            }
        }

        let magnitude = MathPrinter.decimal(abs(coefficient), significantDigits: significantDigits)
        let text = power.isEmpty ? magnitude : (magnitude == "1" ? power : magnitude + power)
        return (coefficient < 0, text)
    }

    static func factorial(_ k: Int) -> Double {
        var result = 1.0
        if k > 1 {
            for i in 2...k { result *= Double(i) }
        }
        return result
    }
}
