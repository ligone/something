import Foundation

/// A number inside a ``MathExpr``: an exact rational or an inexact real.
///
/// Integers and fractions stay exact through parsing, simplification and
/// differentiation, so the derivative of `√x` prints as `1/(2√x)` instead of
/// `0.5/√x`. Decimal literals such as `0.1` are inexact reals, and so is
/// anything computed from them. Exact arithmetic that would overflow `Int`
/// quietly falls back to a real.
public struct MathNumber: Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        /// Lowest terms, with a positive denominator and a numerator that is
        /// never `Int.min`, so negation can't overflow.
        case rational(Int, Int)
        case real(Double)
    }

    let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    /// An exact integer.
    public init(_ integer: Int) {
        storage = integer == Int.min ? .real(Double(integer)) : .rational(integer, 1)
    }

    /// The exact fraction `numerator / denominator`, reduced to lowest terms.
    /// A zero denominator gives an infinite (or NaN) real.
    public init(_ numerator: Int, _ denominator: Int) {
        guard denominator != 0 else {
            storage = .real(Double(numerator) / 0)
            return
        }
        guard numerator != Int.min, denominator != Int.min else {
            storage = .real(Double(numerator) / Double(denominator))
            return
        }
        let divisor = MathNumber.gcd(numerator, denominator)
        var p = numerator / divisor
        var q = denominator / divisor
        if q < 0 {
            p = -p
            q = -q
        }
        storage = .rational(p, q)
    }

    /// An inexact real.
    public init(real value: Double) {
        storage = .real(value)
    }

    public static let zero = MathNumber(0)
    public static let one = MathNumber(1)
    public static let minusOne = MathNumber(-1)
    public static let half = MathNumber(1, 2)

    // MARK: Inspecting

    public var doubleValue: Double {
        switch storage {
        case let .rational(p, q): q == 1 ? Double(p) : Double(p) / Double(q)
        case let .real(value): value
        }
    }

    /// True for rationals, false for reals.
    public var isExact: Bool {
        if case .rational = storage { return true }
        return false
    }

    /// The numerator and denominator of an exact number.
    public var fraction: (numerator: Int, denominator: Int)? {
        if case let .rational(p, q) = storage { return (p, q) }
        return nil
    }

    /// The value of an exact integer.
    public var integerValue: Int? {
        if case let .rational(p, 1) = storage { return p }
        return nil
    }

    /// The value of an exact integer, or of a real that happens to be a
    /// whole number of modest size.
    var wholeValue: Int? {
        switch storage {
        case let .rational(p, q): return q == 1 ? p : nil
        case let .real(value):
            guard value.rounded() == value, abs(value) < 1e15 else { return nil }
            return Int(value)
        }
    }

    public var isZero: Bool { doubleValue == 0 }
    public var isOne: Bool { doubleValue == 1 }
    public var isNegative: Bool { doubleValue < 0 }
    public var isPositive: Bool { doubleValue > 0 }
    public var isFinite: Bool { doubleValue.isFinite }

    public var magnitude: MathNumber { isNegative ? -self : self }

    // MARK: Arithmetic

    public static prefix func - (value: MathNumber) -> MathNumber {
        switch value.storage {
        case let .rational(p, q): MathNumber(storage: .rational(-p, q))
        case let .real(x): MathNumber(real: -x)
        }
    }

    public static func + (lhs: MathNumber, rhs: MathNumber) -> MathNumber {
        if case let .rational(p1, q1) = lhs.storage, case let .rational(p2, q2) = rhs.storage {
            let g = gcd(q1, q2)
            if let a = multiply(p1, q2 / g), let b = multiply(p2, q1 / g),
               let numerator = add(a, b), let denominator = multiply(q1, q2 / g) {
                return MathNumber(numerator, denominator)
            }
        }
        return MathNumber(real: lhs.doubleValue + rhs.doubleValue)
    }

    public static func - (lhs: MathNumber, rhs: MathNumber) -> MathNumber {
        lhs + (-rhs)
    }

    public static func * (lhs: MathNumber, rhs: MathNumber) -> MathNumber {
        if case let .rational(p1, q1) = lhs.storage, case let .rational(p2, q2) = rhs.storage {
            let g1 = gcd(p1, q2)
            let g2 = gcd(p2, q1)
            if let numerator = multiply(p1 / g1, p2 / g2), let denominator = multiply(q1 / g2, q2 / g1) {
                return MathNumber(numerator, denominator)
            }
        }
        return MathNumber(real: lhs.doubleValue * rhs.doubleValue)
    }

    public static func / (lhs: MathNumber, rhs: MathNumber) -> MathNumber {
        if case let .rational(p, q) = rhs.storage, p != 0 {
            return lhs * MathNumber(q, p)
        }
        return MathNumber(real: lhs.doubleValue / rhs.doubleValue)
    }

    public static func += (lhs: inout MathNumber, rhs: MathNumber) { lhs = lhs + rhs }
    public static func *= (lhs: inout MathNumber, rhs: MathNumber) { lhs = lhs * rhs }

    /// `self` raised to `exponent`, or nil when an exact result doesn't exist
    /// (such as `2^(1/2)`, which stays symbolic as `√2`) or would be infinite.
    public func raised(to exponent: MathNumber) -> MathNumber? {
        guard case let .rational(p, q) = storage, case let .rational(m, n) = exponent.storage else {
            let value = MathNumber.power(doubleValue, exponent)
            return value.isFinite ? MathNumber(real: value) : nil
        }
        if n == 1 {
            if m >= 0 {
                guard let numerator = MathNumber.power(p, m), let denominator = MathNumber.power(q, m) else {
                    // Too big to stay exact: a real if it fits, else keep it symbolic.
                    let value = MathNumber.power(doubleValue, exponent)
                    return value.isFinite ? MathNumber(real: value) : nil
                }
                return MathNumber(numerator, denominator)
            }
            guard p != 0, m != Int.min else { return nil }
            return MathNumber(q, p).raised(to: MathNumber(-m))
        }
        // A fractional exponent: exact only for perfect powers, like 8^(2/3) = 4.
        guard let rootP = MathNumber.exactRoot(p, n), let rootQ = MathNumber.exactRoot(q, n) else {
            return nil
        }
        return MathNumber(rootP, rootQ).raised(to: MathNumber(m))
    }

    // MARK: Real powers

    /// `base^exponent` with the real-valued convention for odd roots, so
    /// `(-8)^(1/3)` is `-2` rather than NaN.
    public static func power(_ base: Double, _ exponent: MathNumber) -> Double {
        if base < 0, case let .rational(m, n) = exponent.storage, n % 2 == 1, n != 1 {
            let magnitude = Foundation.pow(-base, Double(m) / Double(n))
            return m % 2 == 0 ? magnitude : -magnitude
        }
        return Foundation.pow(base, exponent.doubleValue)
    }

    // MARK: Approximation

    /// The simplest fraction within `tolerance` (relative) of `value`, whose
    /// denominator is at most `maxDenominator`, found with continued fractions.
    public static func approximating(
        _ value: Double,
        maxDenominator: Int = 1000,
        tolerance: Double = 1e-9
    ) -> MathNumber? {
        guard value.isFinite, abs(value) < 1e15 else { return nil }
        var h0 = 0.0, h1 = 1.0   // numerators of the convergents
        var k0 = 1.0, k1 = 0.0   // denominators of the convergents
        var remainder = value
        for _ in 0..<40 {
            let a = remainder.rounded(.down)
            let h2 = a * h1 + h0
            let k2 = a * k1 + k0
            if k2 > Double(maxDenominator) { break }
            h0 = h1; h1 = h2
            k0 = k1; k1 = k2
            let approximation = h1 / k1
            if abs(approximation - value) <= tolerance * max(abs(value), 1e-300) {
                return MathNumber(Int(h1), Int(k1))
            }
            let fractional = remainder - a
            if fractional < 1e-15 { break }
            remainder = 1 / fractional
        }
        return nil
    }

    // MARK: Integer helpers

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a.magnitude
        var y = b.magnitude
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return x == 0 ? 1 : Int(clamping: x)
    }

    static func add(_ a: Int, _ b: Int) -> Int? {
        let (result, overflow) = a.addingReportingOverflow(b)
        return overflow || result == Int.min ? nil : result
    }

    static func multiply(_ a: Int, _ b: Int) -> Int? {
        let (result, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow || result == Int.min ? nil : result
    }

    /// `base^exponent` for a non-negative exponent, or nil on overflow.
    static func power(_ base: Int, _ exponent: Int) -> Int? {
        var result = 1
        var factor = base
        var remaining = exponent
        while remaining > 0 {
            if remaining & 1 == 1 {
                guard let next = multiply(result, factor) else { return nil }
                result = next
            }
            remaining >>= 1
            if remaining > 0 {
                guard let next = multiply(factor, factor) else { return nil }
                factor = next
            }
        }
        return result
    }

    /// The exact integer `n`-th root of `value`, if it has one.
    static func exactRoot(_ value: Int, _ n: Int) -> Int? {
        guard n > 0 else { return nil }
        if value < 0 {
            guard n % 2 == 1, let root = exactRoot(-value, n) else { return nil }
            return -root
        }
        let guess = Int(Foundation.pow(Double(value), 1 / Double(n)).rounded())
        for candidate in max(0, guess - 1)...(guess + 1) where power(candidate, n) == value {
            return candidate
        }
        return nil
    }
}

extension MathNumber: Comparable {
    public static func < (lhs: MathNumber, rhs: MathNumber) -> Bool {
        lhs.doubleValue < rhs.doubleValue
    }
}

extension MathNumber: CustomStringConvertible {
    public var description: String {
        switch storage {
        case let .rational(p, q): q == 1 ? MathPrinter.integer(p) : "\(MathPrinter.integer(p))/\(q)"
        case let .real(value): MathPrinter.decimal(value)
        }
    }
}
