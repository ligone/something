import Foundation

/// A truncated power series `c₀ + c₁t + c₂t² + … + cₙtⁿ`.
///
/// Arithmetic on these is Taylor-mode automatic differentiation: evaluate an
/// expression with `x = x₀ + t` and every coefficient of the result is a
/// Taylor coefficient `f⁽ᵏ⁾(x₀)/k!`, exact up to rounding, with no symbolic
/// blow-up and no finite-difference error. Each elementary function has a
/// recurrence that comes from a differential equation it satisfies; `exp`,
/// for instance, follows from `b′ = a′b` for `b = e^a`.
struct PowerSeries: Equatable {
    var c: [Double]

    var count: Int { c.count }

    init(_ coefficients: [Double]) {
        c = coefficients
    }

    static func constant(_ value: Double, count: Int) -> PowerSeries {
        var c = [Double](repeating: 0, count: count)
        c[0] = value
        return PowerSeries(c)
    }

    /// The series of `x` around `center`: `center + t`.
    static func variable(at center: Double, count: Int) -> PowerSeries {
        var series = constant(center, count: count)
        if count > 1 { series.c[1] = 1 }
        return series
    }

    static func undefined(count: Int) -> PowerSeries {
        PowerSeries([Double](repeating: .nan, count: count))
    }

    // MARK: Arithmetic

    static func + (a: PowerSeries, b: PowerSeries) -> PowerSeries {
        PowerSeries(zip(a.c, b.c).map { $0 + $1 })
    }

    static func - (a: PowerSeries, b: PowerSeries) -> PowerSeries {
        PowerSeries(zip(a.c, b.c).map { $0 - $1 })
    }

    static func * (a: PowerSeries, b: PowerSeries) -> PowerSeries {
        var c = [Double](repeating: 0, count: a.count)
        for k in 0..<a.count {
            var total = 0.0
            for j in 0...k { total += a.c[j] * b.c[k - j] }
            c[k] = total
        }
        return PowerSeries(c)
    }

    static func / (a: PowerSeries, b: PowerSeries) -> PowerSeries {
        var c = [Double](repeating: 0, count: a.count)
        for k in 0..<a.count {
            var total = a.c[k]
            for j in stride(from: 1, through: k, by: 1) { total -= b.c[j] * c[k - j] }
            c[k] = total / b.c[0]
        }
        return PowerSeries(c)
    }

    func scaled(by factor: Double) -> PowerSeries {
        PowerSeries(c.map { $0 * factor })
    }

    /// The series of the derivative, `d/dt`. The top coefficient is unknown
    /// at this truncation and comes back as 0.
    func derivative() -> PowerSeries {
        var d = [Double](repeating: 0, count: count)
        for k in 0..<(count - 1) { d[k] = Double(k + 1) * c[k + 1] }
        return PowerSeries(d)
    }

    /// The antiderivative with the given constant term.
    func integral(constant: Double) -> PowerSeries {
        var b = [Double](repeating: 0, count: count)
        b[0] = constant
        for k in stride(from: 1, to: count, by: 1) { b[k] = c[k - 1] / Double(k) }
        return PowerSeries(b)
    }

    // MARK: Elementary functions

    func exp() -> PowerSeries {
        var b = [Double](repeating: 0, count: count)
        b[0] = Foundation.exp(c[0])
        for k in stride(from: 1, to: count, by: 1) {
            var total = 0.0
            for j in 1...k { total += Double(j) * c[j] * b[k - j] }
            b[k] = total / Double(k)
        }
        return PowerSeries(b)
    }

    func log() -> PowerSeries {
        var b = [Double](repeating: 0, count: count)
        b[0] = Foundation.log(c[0])
        for k in stride(from: 1, to: count, by: 1) {
            var total = Double(k) * c[k]
            for j in stride(from: 1, to: k, by: 1) { total -= Double(j) * b[j] * c[k - j] }
            b[k] = total / (Double(k) * c[0])
        }
        return PowerSeries(b)
    }

    /// `(sin a, cos a)` together, since each one's recurrence needs the other.
    func sinCos() -> (sin: PowerSeries, cos: PowerSeries) {
        var s = [Double](repeating: 0, count: count)
        var co = [Double](repeating: 0, count: count)
        s[0] = Foundation.sin(c[0])
        co[0] = Foundation.cos(c[0])
        for k in stride(from: 1, to: count, by: 1) {
            var sinTotal = 0.0
            var cosTotal = 0.0
            for j in 1...k {
                sinTotal += Double(j) * c[j] * co[k - j]
                cosTotal += Double(j) * c[j] * s[k - j]
            }
            s[k] = sinTotal / Double(k)
            co[k] = -cosTotal / Double(k)
        }
        return (PowerSeries(s), PowerSeries(co))
    }

    /// `(sinh a, cosh a)` together.
    func sinhCosh() -> (sinh: PowerSeries, cosh: PowerSeries) {
        var s = [Double](repeating: 0, count: count)
        var co = [Double](repeating: 0, count: count)
        s[0] = Foundation.sinh(c[0])
        co[0] = Foundation.cosh(c[0])
        for k in stride(from: 1, to: count, by: 1) {
            var sinhTotal = 0.0
            var coshTotal = 0.0
            for j in 1...k {
                sinhTotal += Double(j) * c[j] * co[k - j]
                coshTotal += Double(j) * c[j] * s[k - j]
            }
            s[k] = sinhTotal / Double(k)
            co[k] = coshTotal / Double(k)
        }
        return (PowerSeries(s), PowerSeries(co))
    }

    /// `aⁿ` for an integer `n`, by repeated squaring, which also works when
    /// `a₀ = 0` (as for `x³` at 0).
    func power(_ n: Int) -> PowerSeries {
        if n < 0 {
            return PowerSeries.constant(1, count: count) / power(-n)
        }
        var result = PowerSeries.constant(1, count: count)
        var base = self
        var remaining = n
        while remaining > 0 {
            if remaining & 1 == 1 { result = result * base }
            remaining >>= 1
            if remaining > 0 { base = base * base }
        }
        return result
    }

    /// `aʳ` for a real exponent, from `a·b′ = r·a′·b`. It needs `a₀ > 0`;
    /// for `a₀ < 0` only odd roots are real, as in `x^(1/3)`.
    func power(_ exponent: MathNumber) -> PowerSeries {
        if let whole = exponent.wholeValue, abs(whole) <= 64 {
            return power(whole)
        }
        let r = exponent.doubleValue
        if c[0] < 0 {
            // (−a)ʳ is real only for odd denominators: aʳ = ±(−a)ʳ.
            guard let (p, q) = exponent.fraction, q % 2 == 1 else { return .undefined(count: count) }
            let magnitude = scaled(by: -1).power(exponent)
            return p % 2 == 0 ? magnitude : magnitude.scaled(by: -1)
        }
        guard c[0] > 0 else {
            // Not analytic at a zero of the base, unless the base vanishes identically.
            if c.allSatisfy({ $0 == 0 }), r > 0 { return .constant(0, count: count) }
            return .undefined(count: count)
        }
        var b = [Double](repeating: 0, count: count)
        b[0] = Foundation.pow(c[0], r)
        for k in stride(from: 1, to: count, by: 1) {
            var total = 0.0
            for j in 1...k { total += ((r + 1) * Double(j) - Double(k)) * c[j] * b[k - j] }
            b[k] = total / (Double(k) * c[0])
        }
        return PowerSeries(b)
    }

    /// `|a|`: analytic wherever `a` doesn't change sign.
    func absoluteValue() -> PowerSeries {
        guard let first = c.firstIndex(where: { $0 != 0 }) else { return self }
        if first == 0 || first % 2 == 0 {
            return c[first] < 0 ? scaled(by: -1) : self
        }
        // |a| has a corner here: only the coefficients below the first
        // nonzero one exist.
        return PowerSeries(c.indices.map { $0 < first ? 0 : .nan })
    }

    func sign() -> PowerSeries {
        guard c[0] != 0 else {
            return c.allSatisfy({ $0 == 0 }) ? self : .undefined(count: count)
        }
        return .constant(c[0] > 0 ? 1 : -1, count: count)
    }
}

extension PowerSeries {
    /// The series of `expression` with `x = center + t`.
    static func evaluate(_ expression: MathExpr, at center: Double, count: Int) -> PowerSeries {
        func series(_ expression: MathExpr) -> PowerSeries {
            switch expression {
            case let .number(value):
                return .constant(value.doubleValue, count: count)
            case .variable:
                return .variable(at: center, count: count)
            case let .constant(constant):
                return .constant(constant.value, count: count)
            case let .sum(terms):
                return terms.dropFirst().reduce(series(terms[0])) { $0 + series($1) }
            case let .product(factors):
                return factors.dropFirst().reduce(series(factors[0])) { $0 * series($1) }
            case let .power(base, exponent):
                if let value = exponent.numberValue {
                    return series(base).power(value)
                }
                if !exponent.containsVariable {
                    return series(base).power(MathNumber(real: exponent.evaluate(at: center)))
                }
                // uᵛ = e^(v·ln u)
                return (series(exponent) * series(base).log()).exp()
            case let .function(function, argument):
                return apply(function, series(argument))
            }
        }
        return series(expression)
    }

    static func apply(_ function: MathFunction, _ a: PowerSeries) -> PowerSeries {
        switch function {
        case .sin: return a.sinCos().sin
        case .cos: return a.sinCos().cos
        case .tan:
            let (s, c) = a.sinCos()
            return s / c
        case .sinh: return a.sinhCosh().sinh
        case .cosh: return a.sinhCosh().cosh
        case .tanh:
            let (s, c) = a.sinhCosh()
            return s / c
        case .exp: return a.exp()
        case .ln: return a.log()
        case .log: return a.log().scaled(by: 1 / Foundation.log(10.0))
        case .sqrt: return a.power(.half)
        case .abs: return a.absoluteValue()
        case .sign: return a.sign()
        case .asin, .acos, .atan:
            // Integrate the derivative: asin′(a) = a′/√(1 − a²), and so on.
            let one = PowerSeries.constant(1, count: a.count)
            let slope: PowerSeries
            let start: Double
            switch function {
            case .asin:
                slope = a.derivative() / (one - a * a).power(.half)
                start = Foundation.asin(a.c[0])
            case .acos:
                slope = (a.derivative() / (one - a * a).power(.half)).scaled(by: -1)
                start = Foundation.acos(a.c[0])
            default:
                slope = a.derivative() / (one + a * a)
                start = Foundation.atan(a.c[0])
            }
            return slope.integral(constant: start)
        }
    }
}
