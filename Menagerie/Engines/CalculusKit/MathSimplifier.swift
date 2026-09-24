/// Rewrites expressions into a canonical, simplified form.
///
/// The rules follow the "automatic simplification" of classic computer
/// algebra systems:
///
/// * Sums and products are flattened, and numbers are folded exactly.
/// * Identities disappear: `0 + a`, `1·a`, `0·a`, `a^1`, `a^0`, `−(−a)`.
/// * Like terms are collected (`2x + 3x = 5x`) and so are like factors
///   (`x·x = x²`, `x^a·x^b = x^(a+b)`, `x²/x = x`).
/// * Integer powers distribute over products (`(2x)² = 4x²`) and nest
///   (`(x²)³ = x⁶`), and `√(u²) = |u|`.
/// * `sqrt` and `exp` become powers, special values fold (`sin(π) = 0`,
///   `ln(e) = 1`), and odd and even functions absorb signs.
/// * Operands are sorted into a canonical order, so equal expressions are
///   structurally equal. The order is also chosen to read naturally:
///   `3x² − 3`, `x²·cos(x) + 2x·sin(x)`.
///
/// Every builder assumes its operands are already simplified, which is what
/// lets ``Derivative`` produce simplified results as it goes.
public enum MathSimplifier {
    /// Simplifies `expression`, repeating passes until nothing changes.
    public static func simplify(_ expression: MathExpr) -> MathExpr {
        var current = expression
        for _ in 0..<16 {
            let next = pass(current)
            if next == current { return next }
            current = next
        }
        return current
    }

    /// One bottom-up rewrite of the whole tree.
    static func pass(_ expression: MathExpr) -> MathExpr {
        switch expression {
        case .number, .variable, .constant:
            return expression
        case let .sum(terms):
            return makeSum(terms.map(pass))
        case let .product(factors):
            return makeProduct(factors.map(pass))
        case let .power(base, exponent):
            return makePower(pass(base), pass(exponent))
        case let .function(function, argument):
            return makeFunction(function, pass(argument))
        }
    }

    // MARK: - Sums

    /// The simplified sum of simplified terms.
    static func makeSum(_ terms: [MathExpr]) -> MathExpr {
        var constant = MathNumber.zero
        var order: [MathExpr] = []
        var coefficients: [MathExpr: MathNumber] = [:]

        func add(_ term: MathExpr, scale: MathNumber) {
            switch term {
            case let .sum(inner):
                for innerTerm in inner { add(innerTerm, scale: scale) }
            case let .number(value):
                constant += value * scale
            default:
                let (coefficient, rest) = splitCoefficient(term)
                if case let .sum(inner) = rest {
                    // c·(a + b) inside a sum is distributed, so it can combine.
                    for innerTerm in inner { add(innerTerm, scale: scale * coefficient) }
                } else if let existing = coefficients[rest] {
                    coefficients[rest] = existing + coefficient * scale
                } else {
                    order.append(rest)
                    coefficients[rest] = coefficient * scale
                }
            }
        }
        for term in terms { add(term, scale: .one) }

        var result: [MathExpr] = []
        for rest in order {
            guard let coefficient = coefficients[rest], !coefficient.isZero else { continue }
            result.append(attach(coefficient, to: rest))
        }
        if !constant.isZero {
            result.append(.number(constant))
        }
        result.sort(by: sumPrecedes)

        switch result.count {
        case 0: return .zero
        case 1: return result[0]
        default: return .sum(result)
        }
    }

    /// Splits `3x²` into `(3, x²)`. Terms without a numeric factor get 1.
    static func splitCoefficient(_ term: MathExpr) -> (MathNumber, MathExpr) {
        if case let .product(factors) = term, case let .number(coefficient) = factors.first {
            let rest = Array(factors.dropFirst())
            return (coefficient, rest.count == 1 ? rest[0] : .product(rest))
        }
        return (.one, term)
    }

    /// `coefficient · rest`, for a `rest` without a numeric factor.
    static func attach(_ coefficient: MathNumber, to rest: MathExpr) -> MathExpr {
        if coefficient.isOne { return rest }
        if case let .product(factors) = rest {
            return .product([.number(coefficient)] + factors)
        }
        return .product([.number(coefficient), rest])
    }

    // MARK: - Products

    /// The simplified product of simplified factors.
    static func makeProduct(_ factors: [MathExpr]) -> MathExpr {
        var coefficient = MathNumber.one
        var bases: [MathExpr] = []
        var exponents: [MathExpr: [MathExpr]] = [:]

        func collect(_ base: MathExpr, _ exponent: MathExpr) {
            if exponents[base] == nil {
                bases.append(base)
                exponents[base] = [exponent]
            } else {
                exponents[base]?.append(exponent)
            }
        }

        func add(_ factor: MathExpr) {
            switch factor {
            case let .product(inner):
                for innerFactor in inner { add(innerFactor) }
            case let .number(value):
                coefficient *= value
            case let .power(base, exponent):
                collect(base, exponent)
            default:
                collect(factor, .one)
            }
        }
        for factor in factors { add(factor) }
        if coefficient.isZero { return .zero }

        var result: [MathExpr] = []
        for base in bases {
            let combined = makePower(base, makeSum(exponents[base] ?? []))
            switch combined {
            case let .number(value):
                coefficient *= value
            case let .product(inner):
                for factor in inner {
                    if case let .number(value) = factor {
                        coefficient *= value
                    } else {
                        result.append(factor)
                    }
                }
            default:
                result.append(combined)
            }
        }
        if coefficient.isZero { return .zero }
        result.sort(by: productPrecedes)

        // Normalize negatives: −(a − b) reads better as b − a.
        if result.count == 1, coefficient.doubleValue == -1, case let .sum(terms) = result[0] {
            return makeSum(terms.map { negate($0) })
        }
        if result.isEmpty { return .number(coefficient) }
        if coefficient.isOne {
            return result.count == 1 ? result[0] : .product(result)
        }
        return .product([.number(coefficient)] + result)
    }

    /// `−expression`, simplified.
    static func negate(_ expression: MathExpr) -> MathExpr {
        if case let .number(value) = expression { return .number(-value) }
        let (coefficient, rest) = splitCoefficient(expression)
        if case .sum = rest { return makeProduct([.minusOne, expression]) }
        return attach(-coefficient, to: rest)
    }

    /// `1/expression`, simplified.
    static func reciprocal(_ expression: MathExpr) -> MathExpr {
        makePower(expression, .minusOne)
    }

    /// If `expression` carries a minus sign (a negative number, or a product
    /// with a negative coefficient), the expression without it.
    static func withoutMinusSign(_ expression: MathExpr) -> MathExpr? {
        switch expression {
        case let .number(value) where value.isNegative:
            return .number(-value)
        case .product:
            let (coefficient, rest) = splitCoefficient(expression)
            guard coefficient.isNegative else { return nil }
            return attach(-coefficient, to: rest)
        default:
            return nil
        }
    }

    // MARK: - Powers

    /// The simplified power of a simplified base and exponent.
    static func makePower(_ base: MathExpr, _ exponent: MathExpr) -> MathExpr {
        let exponentValue = exponent.numberValue
        if let exponentValue {
            if exponentValue.isZero { return .one }
            if exponentValue.isOne { return base }
        }

        switch base {
        case let .number(value):
            if value.isOne { return .one }
            if let exponentValue {
                if value.isZero, exponentValue.isPositive { return .zero }
                if let folded = value.raised(to: exponentValue) { return .number(folded) }
            }

        case let .power(innerBase, innerExponent):
            guard let exponentValue else { break }
            // (u^a)^n = u^(a·n) for integer n.
            if exponentValue.integerValue != nil {
                return makePower(innerBase, makeProduct([innerExponent, exponent]))
            }
            // (u^(2k))^r = |u|^(2k·r), because u^(2k) is never negative.
            if let even = innerExponent.numberValue?.integerValue, even % 2 == 0,
               let combined = (MathNumber(even) * exponentValue).integerValue {
                return makePower(makeFunction(.abs, innerBase), .integer(combined))
            }

        case let .product(factors):
            guard let exponentValue else { break }
            // (ab)^n = aⁿbⁿ for integer n.
            if exponentValue.integerValue != nil {
                return makeProduct(factors.map { makePower($0, exponent) })
            }
            // (c·u)^r = c^r·u^r when c > 0.
            if case let .number(coefficient) = factors.first, coefficient.isPositive {
                let rest = factors.count == 2 ? factors[1] : .product(Array(factors.dropFirst()))
                return makeProduct([makePower(.number(coefficient), exponent), makePower(rest, exponent)])
            }

        case let .function(.abs, inner):
            // |u|^(2k) = u^(2k).
            if let even = exponentValue?.integerValue, even % 2 == 0 {
                return makePower(inner, exponent)
            }

        default:
            break
        }
        return .power(base, exponent)
    }

    // MARK: - Functions

    /// The simplified application of `function` to a simplified argument.
    static func makeFunction(_ function: MathFunction, _ argument: MathExpr) -> MathExpr {
        switch function {
        case .sqrt: return makePower(argument, .number(.half))
        case .exp: return makePower(.e, argument)
        default: break
        }

        if let value = specialValue(of: function, at: argument) {
            return value
        }

        // Functions of inexact numbers are evaluated.
        if case let .number(value) = argument, !value.isExact {
            let result = function.evaluate(value.doubleValue)
            if result.isFinite { return .real(result) }
        }

        // Odd functions pull a minus sign out; even ones drop it.
        if function.isOdd || function.isEven, let positive = withoutMinusSign(argument) {
            let inner = makeFunction(function, positive)
            return function.isOdd ? makeProduct([.minusOne, inner]) : inner
        }

        if function == .abs, let simpler = simplifiedAbsoluteValue(of: argument) {
            return simpler
        }
        if function == .sign, case .function(.sign, _) = argument {
            return argument
        }
        return .function(function, argument)
    }

    /// Exact values such as `sin(π) = 0`, `ln(e) = 1` and `log(1000) = 3`.
    static func specialValue(of function: MathFunction, at argument: MathExpr) -> MathExpr? {
        let exact = argument.numberValue.flatMap { $0.isExact ? $0 : nil }
        switch function {
        case .sin, .cos, .tan:
            guard let quarterTurns = quarterTurns(argument) else { return nil }
            switch function {
            case .sin: return .integer([0, 1, 0, -1][quarterTurns])
            case .cos: return .integer([1, 0, -1, 0][quarterTurns])
            default: return quarterTurns % 2 == 0 ? .zero : nil
            }
        case .asin, .atan, .sinh, .tanh:
            if exact?.isZero == true { return .zero }
            if exact?.isOne == true {
                if function == .asin { return makeProduct([.fraction(1, 2), .pi]) }
                if function == .atan { return makeProduct([.fraction(1, 4), .pi]) }
            }
        case .acos:
            if exact?.isOne == true { return .zero }
            if exact?.isZero == true { return makeProduct([.fraction(1, 2), .pi]) }
            if exact?.doubleValue == -1 { return .pi }
        case .cosh:
            if exact?.isZero == true { return .one }
        case .ln:
            if exact?.isOne == true { return .zero }
            if argument == .e { return .one }
            if case let .power(.constant(.e), power) = argument { return power }
        case .log:
            if let exact, let exponent = powerOfTen(exact) { return .integer(exponent) }
            if case let .power(.number(ten), power) = argument, ten == MathNumber(10) { return power }
        case .abs:
            if let value = argument.numberValue { return .number(value.magnitude) }
            if case .constant = argument { return argument }
        case .sign:
            if let value = argument.numberValue {
                let sign = MathFunction.sign.evaluate(value.doubleValue)
                return sign.isNaN ? nil : .integer(Int(sign))
            }
            if case .constant = argument { return .one }
        case .exp, .sqrt:
            break
        }
        return nil
    }

    /// For `k·π/2` with integer `k`, the value of `k mod 4`.
    static func quarterTurns(_ argument: MathExpr) -> Int? {
        let multiple: MathNumber
        switch argument {
        case let .number(value) where value.isExact && value.isZero:
            return 0
        case .constant(.pi):
            multiple = .one
        case let .product(factors):
            guard factors.count == 2, case let .number(value) = factors[0], value.isExact, factors[1] == .pi else {
                return nil
            }
            multiple = value
        default:
            return nil
        }
        guard let halves = (multiple * MathNumber(2)).integerValue else { return nil }
        return ((halves % 4) + 4) % 4
    }

    /// `k` when `value` is exactly `10^k`.
    static func powerOfTen(_ value: MathNumber) -> Int? {
        guard let (numerator, denominator) = value.fraction, numerator > 0 else { return nil }
        func exponent(_ n: Int) -> Int? {
            var n = n
            var count = 0
            while n > 1 {
                guard n % 10 == 0 else { return nil }
                n /= 10
                count += 1
            }
            return count
        }
        if denominator == 1 { return exponent(numerator) }
        if numerator == 1, let k = exponent(denominator) { return -k }
        return nil
    }

    /// `|π| = π`, `||u|| = |u|`, `|u²| = u²`, `|e^u| = e^u` and `|3u| = 3|u|`.
    static func simplifiedAbsoluteValue(of argument: MathExpr) -> MathExpr? {
        switch argument {
        case .function(.abs, _):
            return argument
        case let .power(base, exponent):
            if base == .e || base == .pi { return argument }
            if let even = exponent.numberValue?.integerValue, even % 2 == 0 { return argument }
        case let .product(factors):
            if case let .number(coefficient) = factors.first, coefficient.isPositive {
                let rest = factors.count == 2 ? factors[1] : .product(Array(factors.dropFirst()))
                return makeProduct([.number(coefficient), makeFunction(.abs, rest)])
            }
        default:
            break
        }
        return nil
    }

    // MARK: - Canonical order

    static func baseAndExponent(_ factor: MathExpr) -> (MathExpr, MathExpr) {
        if case let .power(base, exponent) = factor { return (base, exponent) }
        return (factor, .one)
    }

    /// Groups factors so products read naturally: numbers, then constants
    /// (`π`, `√2`), powers of x, exponentials (`e^x`, `x^x`), functions,
    /// sums, and anything else.
    static func rank(_ factor: MathExpr) -> Int {
        let (base, exponent) = baseAndExponent(factor)
        if exponent.containsVariable { return 3 }
        switch base {
        case .number, .constant: return 1
        case .variable: return 2
        case .function: return 4
        case .sum: return base.containsVariable ? 5 : 1
        case .product, .power: return 6
        }
    }

    static func compareFactors(_ a: MathExpr, _ b: MathExpr) -> Int {
        let rankA = rank(a)
        let rankB = rank(b)
        if rankA != rankB { return rankA < rankB ? -1 : 1 }
        let (baseA, exponentA) = baseAndExponent(a)
        let (baseB, exponentB) = baseAndExponent(b)
        let order = compare(baseA, baseB)
        return order != 0 ? order : compare(exponentA, exponentB)
    }

    static func productPrecedes(_ a: MathExpr, _ b: MathExpr) -> Bool {
        compareFactors(a, b) < 0
    }

    /// Sums read in descending powers of x (`x³ + 2x − 1`), with numbers last.
    static func sumPrecedes(_ a: MathExpr, _ b: MathExpr) -> Bool {
        let aIsNumber = a.numberValue != nil
        let bIsNumber = b.numberValue != nil
        if aIsNumber || bIsNumber { return !aIsNumber && bIsNumber }

        let keyA = termKey(a)
        let keyB = termKey(b)
        if keyA.degree != keyB.degree { return keyA.degree > keyB.degree }
        if keyA.isConstant != keyB.isConstant { return !keyA.isConstant }
        if keyA.others.isEmpty != keyB.others.isEmpty { return keyB.others.isEmpty }
        for (factorA, factorB) in zip(keyA.others, keyB.others) {
            let order = compareFactors(factorA, factorB)
            if order != 0 { return order < 0 }
        }
        if keyA.others.count != keyB.others.count { return keyA.others.count < keyB.others.count }
        return compare(a, b) < 0
    }

    /// A term's power of x, and its other non-numeric factors.
    static func termKey(_ term: MathExpr) -> (degree: Double, isConstant: Bool, others: [MathExpr]) {
        let (_, rest) = splitCoefficient(term)
        let factors: [MathExpr]
        if case let .product(inner) = rest { factors = inner } else { factors = [rest] }
        var degree = 0.0
        var others: [MathExpr] = []
        for factor in factors {
            switch factor {
            case .variable:
                degree += 1
            case let .power(.variable, .number(exponent)):
                degree += exponent.doubleValue
            default:
                others.append(factor)
            }
        }
        return (degree, !term.containsVariable, others)
    }

    /// A total order on expressions: -1, 0 or 1.
    static func compare(_ a: MathExpr, _ b: MathExpr) -> Int {
        let kindA = kindIndex(a)
        let kindB = kindIndex(b)
        if kindA != kindB { return kindA < kindB ? -1 : 1 }

        switch (a, b) {
        case let (.number(x), .number(y)):
            if x.doubleValue != y.doubleValue { return x.doubleValue < y.doubleValue ? -1 : 1 }
            if x.isExact != y.isExact { return x.isExact ? -1 : 1 }
            return 0
        case let (.constant(x), .constant(y)):
            let indexX = MathConstant.allCases.firstIndex(of: x) ?? 0
            let indexY = MathConstant.allCases.firstIndex(of: y) ?? 0
            return indexX == indexY ? 0 : (indexX < indexY ? -1 : 1)
        case let (.function(f, u), .function(g, v)):
            let indexF = MathFunction.allCases.firstIndex(of: f) ?? 0
            let indexG = MathFunction.allCases.firstIndex(of: g) ?? 0
            if indexF != indexG { return indexF < indexG ? -1 : 1 }
            return compare(u, v)
        case let (.power(baseA, exponentA), .power(baseB, exponentB)):
            let order = compare(baseA, baseB)
            return order != 0 ? order : compare(exponentA, exponentB)
        case let (.sum(xs), .sum(ys)), let (.product(xs), .product(ys)):
            for (x, y) in zip(xs, ys) {
                let order = compare(x, y)
                if order != 0 { return order }
            }
            return xs.count == ys.count ? 0 : (xs.count < ys.count ? -1 : 1)
        default:
            return 0
        }
    }

    private static func kindIndex(_ expression: MathExpr) -> Int {
        switch expression {
        case .number: 0
        case .constant: 1
        case .variable: 2
        case .power: 3
        case .function: 4
        case .product: 5
        case .sum: 6
        }
    }
}
