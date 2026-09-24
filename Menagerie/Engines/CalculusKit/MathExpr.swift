import Foundation

/// A symbolic expression in one real variable, `x`.
///
/// Subtraction and division have no cases of their own: `a − b` is
/// `a + (−1)·b` and `a / b` is `a · b^(−1)`. Sums and products are n-ary, so
/// the simplifier can flatten them, sort them and collect like terms, the way
/// a computer algebra system does. ``MathPrinter`` turns the canonical form
/// back into familiar notation.
public indirect enum MathExpr: Hashable, Sendable {
    case number(MathNumber)
    /// The variable `x`.
    case variable
    case constant(MathConstant)
    case sum([MathExpr])
    case product([MathExpr])
    case power(MathExpr, MathExpr)
    case function(MathFunction, MathExpr)
}

/// The named constants the parser understands.
public enum MathConstant: String, CaseIterable, Hashable, Sendable {
    case pi
    case e

    public var value: Double {
        switch self {
        case .pi: Double.pi
        case .e: 2.718281828459045
        }
    }

    public var symbol: String {
        switch self {
        case .pi: "π"
        case .e: "e"
        }
    }
}

/// The elementary functions the parser understands.
///
/// `sqrt` and `exp` are accepted as input but the simplifier rewrites them as
/// powers (`x^(1/2)` and `e^x`), so every power obeys the same rules.
public enum MathFunction: String, CaseIterable, Hashable, Sendable {
    case sin, cos, tan
    case asin, acos, atan
    case sinh, cosh, tanh
    case exp, ln, log, sqrt
    case abs, sign

    /// The name used when printing.
    public var name: String {
        switch self {
        case .sign: "sgn"
        default: rawValue
        }
    }

    /// Trigonometric and hyperbolic functions print powers the traditional
    /// way, as in `sin²(x)`.
    var usesPrefixPowerNotation: Bool {
        switch self {
        case .sin, .cos, .tan, .sinh, .cosh, .tanh: true
        default: false
        }
    }

    /// True when `f(−u) = −f(u)`.
    var isOdd: Bool {
        switch self {
        case .sin, .tan, .asin, .atan, .sinh, .tanh, .sign: true
        default: false
        }
    }

    /// True when `f(−u) = f(u)`.
    var isEven: Bool {
        switch self {
        case .cos, .cosh, .abs: true
        default: false
        }
    }

    public func evaluate(_ u: Double) -> Double {
        switch self {
        case .sin: Foundation.sin(u)
        case .cos: Foundation.cos(u)
        case .tan: Foundation.tan(u)
        case .asin: Foundation.asin(u)
        case .acos: Foundation.acos(u)
        case .atan: Foundation.atan(u)
        case .sinh: Foundation.sinh(u)
        case .cosh: Foundation.cosh(u)
        case .tanh: Foundation.tanh(u)
        case .exp: Foundation.exp(u)
        case .ln: Foundation.log(u)
        case .log: Foundation.log10(u)
        case .sqrt: u.squareRoot()
        case .abs: Swift.abs(u)
        case .sign: u > 0 ? 1 : (u < 0 ? -1 : (u == 0 ? 0 : .nan))
        }
    }
}

// MARK: - Building

extension MathExpr {
    public static let x = MathExpr.variable
    public static let zero = MathExpr.number(.zero)
    public static let one = MathExpr.number(.one)
    public static let minusOne = MathExpr.number(.minusOne)
    public static let pi = MathExpr.constant(.pi)
    public static let e = MathExpr.constant(.e)

    public static func integer(_ value: Int) -> MathExpr {
        .number(MathNumber(value))
    }

    public static func fraction(_ numerator: Int, _ denominator: Int) -> MathExpr {
        .number(MathNumber(numerator, denominator))
    }

    public static func real(_ value: Double) -> MathExpr {
        .number(MathNumber(real: value))
    }
}

// MARK: - Inspecting

extension MathExpr {
    /// True when the expression depends on `x`.
    public var containsVariable: Bool {
        switch self {
        case .number, .constant: false
        case .variable: true
        case let .sum(terms): terms.contains { $0.containsVariable }
        case let .product(factors): factors.contains { $0.containsVariable }
        case let .power(base, exponent): base.containsVariable || exponent.containsVariable
        case let .function(_, argument): argument.containsVariable
        }
    }

    /// The number this expression is, if it is one.
    public var numberValue: MathNumber? {
        if case let .number(value) = self { return value }
        return nil
    }

    /// The number of nodes in the tree: a rough measure of complexity.
    public var nodeCount: Int {
        switch self {
        case .number, .variable, .constant: 1
        case let .sum(terms): terms.reduce(1) { $0 + $1.nodeCount }
        case let .product(factors): factors.reduce(1) { $0 + $1.nodeCount }
        case let .power(base, exponent): 1 + base.nodeCount + exponent.nodeCount
        case let .function(_, argument): 1 + argument.nodeCount
        }
    }

    /// The expression with its simplifications applied. See ``MathSimplifier``.
    public func simplified() -> MathExpr {
        MathSimplifier.simplify(self)
    }

    /// The simplified derivative with respect to `x`. See ``Derivative``.
    public func derivative() -> MathExpr {
        Derivative.of(self)
    }
}

// MARK: - Evaluating

extension MathExpr {
    /// The value at `x`, walking the tree. Undefined points give NaN or ±∞.
    /// For evaluating many points, ``CompiledExpr`` is much faster.
    public func evaluate(at x: Double) -> Double {
        switch self {
        case let .number(value):
            return value.doubleValue
        case .variable:
            return x
        case let .constant(constant):
            return constant.value
        case let .sum(terms):
            var total = 0.0
            for term in terms { total += term.evaluate(at: x) }
            return total
        case let .product(factors):
            var total = 1.0
            for factor in factors { total *= factor.evaluate(at: x) }
            return total
        case let .power(base, exponent):
            let b = base.evaluate(at: x)
            if case let .number(n) = exponent { return MathNumber.power(b, n) }
            return Foundation.pow(b, exponent.evaluate(at: x))
        case let .function(function, argument):
            return function.evaluate(argument.evaluate(at: x))
        }
    }
}

extension MathExpr: CustomStringConvertible {
    /// Human-friendly notation, such as `x²·cos(x) + 2x·sin(x)`.
    public var description: String {
        MathPrinter.format(self)
    }
}
