/// Everything the workbench needs to know about one function: its
/// simplified form, its first and second derivatives, and fast evaluators
/// for all three.
///
///     let analysis = try FunctionAnalysis(parsing: "sin(x)·x²")
///     analysis.firstDerivative.description   // "x²·cos(x) + 2x·sin(x)"
///     analysis.features(in: -5...5).roots    // [−3.14159…, 0, 3.14159…]
public struct FunctionAnalysis: Sendable {
    /// The text the function was parsed from.
    public let source: String
    /// f, simplified.
    public let function: MathExpr
    /// f′, simplified.
    public let firstDerivative: MathExpr
    /// f″, simplified.
    public let secondDerivative: MathExpr

    public let f: CompiledExpr
    public let fPrime: CompiledExpr
    public let fDoublePrime: CompiledExpr

    /// Parses, simplifies and differentiates `source`.
    /// - Throws: ``MathParseError`` if `source` isn't a valid expression.
    public init(parsing source: String) throws {
        self.init(try MathParser.parse(source), source: source)
    }

    public init(_ expression: MathExpr, source: String? = nil) {
        let function = MathSimplifier.simplify(expression)
        let firstDerivative = Derivative.of(function)
        let secondDerivative = Derivative.of(firstDerivative)
        self.source = source ?? function.description
        self.function = function
        self.firstDerivative = firstDerivative
        self.secondDerivative = secondDerivative
        f = CompiledExpr(function)
        fPrime = CompiledExpr(firstDerivative)
        fDoublePrime = CompiledExpr(secondDerivative)
    }

    /// Roots, extrema and inflection points in `interval`. Constant
    /// functions have no roots to report, lines no extrema, and so on.
    public func features(in interval: ClosedRange<Double>, samples: Int = 2048, limit: Int = 100) -> CurveFeatures {
        guard interval.upperBound > interval.lowerBound, function.numberValue == nil else {
            return CurveFeatures(interval: interval)
        }
        let f = self.f
        let fPrime = self.fPrime
        let fDoublePrime = self.fDoublePrime
        let hasExtrema = firstDerivative.numberValue == nil
        let hasInflections = secondDerivative.numberValue == nil
        return CurveFeatures.find(
            function: { f($0) },
            derivative: hasExtrema ? { fPrime($0) } : nil,
            secondDerivative: hasInflections ? { fDoublePrime($0) } : nil,
            in: interval,
            samples: samples,
            limit: limit
        )
    }

    /// `∫ f(x) dx` from `a` to `b`.
    public func integral(from a: Double, to b: Double) -> IntegralResult {
        let f = self.f
        return Integrator.adaptiveSimpson({ f($0) }, from: a, to: b)
    }

    /// The Taylor expansion of f around `center`.
    public func taylorSeries(at center: Double, order: Int) -> TaylorSeries {
        TaylorSeries(function, at: center, order: order)
    }
}
