/// Symbolic differentiation with respect to `x`.
///
/// Each rule builds its result with the simplifier's constructors, so
/// derivatives come out simplified as they're formed, and a final pass
/// tidies whatever is left. The rules:
///
/// * sums, the product rule for n factors, and the chain rule for every
///   elementary function;
/// * the power rule `(uⁿ)′ = n·uⁿ⁻¹·u′` for exponents without x, which covers
///   quotients too because `u/v = u·v⁻¹`;
/// * `(aᵛ)′ = aᵛ·ln(a)·v′` for bases without x;
/// * the general `(uᵛ)′ = uᵛ·(v′·ln(u) + v·u′/u)`, from writing `uᵛ` as
///   `e^(v·ln(u))`.
public enum Derivative {
    /// The simplified derivative of `expression`.
    public static func of(_ expression: MathExpr) -> MathExpr {
        of(expression, order: 1)
    }

    /// The simplified derivative of the given order (0 returns the
    /// simplified expression itself).
    public static func of(_ expression: MathExpr, order: Int) -> MathExpr {
        var result = MathSimplifier.simplify(expression)
        for _ in 0..<max(0, order) {
            result = MathSimplifier.simplify(differentiate(result))
        }
        return result
    }

    /// The derivative of a simplified expression.
    static func differentiate(_ expression: MathExpr) -> MathExpr {
        guard expression.containsVariable else { return .zero }

        switch expression {
        case .number, .constant:
            return .zero

        case .variable:
            return .one

        case let .sum(terms):
            return MathSimplifier.makeSum(terms.map(differentiate))

        case let .product(factors):
            // (f·g·h)′ = f′·g·h + f·g′·h + f·g·h′
            var terms: [MathExpr] = []
            for (index, factor) in factors.enumerated() where factor.containsVariable {
                var copy = factors
                copy[index] = differentiate(factor)
                terms.append(MathSimplifier.makeProduct(copy))
            }
            return MathSimplifier.makeSum(terms)

        case let .power(base, exponent):
            if !exponent.containsVariable {
                let lowered = MathSimplifier.makePower(base, MathSimplifier.makeSum([exponent, .minusOne]))
                return MathSimplifier.makeProduct([exponent, lowered, differentiate(base)])
            }
            if !base.containsVariable {
                return MathSimplifier.makeProduct([
                    expression,
                    MathSimplifier.makeFunction(.ln, base),
                    differentiate(exponent),
                ])
            }
            let logarithmic = MathSimplifier.makeSum([
                MathSimplifier.makeProduct([differentiate(exponent), MathSimplifier.makeFunction(.ln, base)]),
                MathSimplifier.makeProduct([exponent, differentiate(base), MathSimplifier.reciprocal(base)]),
            ])
            return MathSimplifier.makeProduct([expression, logarithmic])

        case let .function(function, argument):
            let inner = differentiate(argument)
            if inner == .zero { return .zero }
            return MathSimplifier.makeProduct([outerDerivative(function, at: argument), inner])
        }
    }

    /// `f′(u)`, the derivative of the outer function at its argument.
    static func outerDerivative(_ function: MathFunction, at u: MathExpr) -> MathExpr {
        typealias S = MathSimplifier
        let uSquared = S.makePower(u, .integer(2))
        switch function {
        case .sin:
            return S.makeFunction(.cos, u)
        case .cos:
            return S.negate(S.makeFunction(.sin, u))
        case .tan:
            return S.makePower(S.makeFunction(.cos, u), .integer(-2))
        case .asin:
            return S.makePower(S.makeSum([.one, S.negate(uSquared)]), .fraction(-1, 2))
        case .acos:
            return S.negate(S.makePower(S.makeSum([.one, S.negate(uSquared)]), .fraction(-1, 2)))
        case .atan:
            return S.reciprocal(S.makeSum([.one, uSquared]))
        case .sinh:
            return S.makeFunction(.cosh, u)
        case .cosh:
            return S.makeFunction(.sinh, u)
        case .tanh:
            return S.makePower(S.makeFunction(.cosh, u), .integer(-2))
        case .exp:
            return S.makePower(.e, u)
        case .ln:
            return S.reciprocal(u)
        case .log:
            return S.reciprocal(S.makeProduct([u, S.makeFunction(.ln, .integer(10))]))
        case .sqrt:
            return S.makeProduct([.fraction(1, 2), S.makePower(u, .fraction(-1, 2))])
        case .abs:
            return S.makeFunction(.sign, u)
        case .sign:
            return .zero
        }
    }
}
