/// A `Double` split into two `Float`s whose sum carries (almost) all of its
/// precision: `hi` holds the leading 24 bits of the mantissa and `lo` the
/// rounding error of `hi`.
///
/// GPUs compute in 32-bit floats, which run out of precision at about 10⁴×
/// magnification. Passing coordinates as `hi + lo` pairs and doing
/// "double-float" arithmetic in the shader (error-free sums and products)
/// buys roughly 48 bits: enough to zoom ten billion times deeper.
public struct DoubleFloat: Equatable, Sendable {
    public var hi: Float
    public var lo: Float

    public init(_ value: Double) {
        hi = Float(value)
        lo = Float(value - Double(hi))
    }

    public init(hi: Float, lo: Float) {
        self.hi = hi
        self.lo = lo
    }

    public var doubleValue: Double {
        Double(hi) + Double(lo)
    }

    // The reference implementations below mirror the shader's arithmetic, so
    // tests can check that the algorithms really are error-free.

    /// Knuth's TwoSum: `s + e == a + b` exactly.
    public static func twoSum(_ a: Float, _ b: Float) -> DoubleFloat {
        let s = a + b
        let bb = s - a
        let e = (a - (s - bb)) + (b - bb)
        return DoubleFloat(hi: s, lo: e)
    }

    /// Dekker's TwoProduct via fused multiply-add: `p + e == a · b` exactly.
    public static func twoProduct(_ a: Float, _ b: Float) -> DoubleFloat {
        let p = a * b
        let e = (-p).addingProduct(a, b) // fma(a, b, -p), rounded once
        return DoubleFloat(hi: p, lo: e)
    }

    public static func + (a: DoubleFloat, b: DoubleFloat) -> DoubleFloat {
        var s = twoSum(a.hi, b.hi)
        let t = twoSum(a.lo, b.lo)
        s.lo += t.hi
        s = quickTwoSum(s.hi, s.lo)
        s.lo += t.lo
        return quickTwoSum(s.hi, s.lo)
    }

    public static func * (a: DoubleFloat, b: DoubleFloat) -> DoubleFloat {
        var p = twoProduct(a.hi, b.hi)
        p.lo += a.hi * b.lo + a.lo * b.hi
        return quickTwoSum(p.hi, p.lo)
    }

    public static prefix func - (a: DoubleFloat) -> DoubleFloat {
        DoubleFloat(hi: -a.hi, lo: -a.lo)
    }

    private static func quickTwoSum(_ a: Float, _ b: Float) -> DoubleFloat {
        let s = a + b
        let e = b - (s - a)
        return DoubleFloat(hi: s, lo: e)
    }
}
