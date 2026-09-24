// Vector helpers on the stdlib `SIMD3<Float>`.
//
// The public API exchanges plain `SIMD3<Float>` values. These helpers are
// internal: TracerKit never adds public extensions to stdlib types, so it
// can't collide with `simd` or other modules in the app. They're marked
// `@inlinable` so every file can inline them, even when the engine is built
// without whole-module optimization.

/// A linear-light RGB triple, used for albedo, radiance and path throughput.
public typealias TracerColor = SIMD3<Float>

@usableFromInline
typealias Vec3 = SIMD3<Float>

@inlinable @inline(__always)
func dot(_ a: Vec3, _ b: Vec3) -> Float {
    a.x * b.x + a.y * b.y + a.z * b.z
}

@inlinable @inline(__always)
func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
    Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

@inlinable @inline(__always)
func lengthSquared(_ v: Vec3) -> Float {
    dot(v, v)
}

@inlinable @inline(__always)
func length(_ v: Vec3) -> Float {
    dot(v, v).squareRoot()
}

/// Returns `v` scaled to unit length. A zero vector stays zero instead of
/// becoming NaN, which keeps degenerate input from poisoning a whole image.
@inlinable @inline(__always)
func normalize(_ v: Vec3) -> Vec3 {
    let squared = dot(v, v)
    guard squared > 0 else { return v }
    return v * (1 / squared.squareRoot())
}

/// Mirror reflection of the incoming direction `v` about the unit normal `n`.
@inlinable @inline(__always)
func reflect(_ v: Vec3, _ n: Vec3) -> Vec3 {
    v - n * (2 * dot(v, n))
}

@inlinable @inline(__always)
func maxComponent(_ v: Vec3) -> Float {
    max(v.x, max(v.y, v.z))
}

@inlinable @inline(__always)
func maxMagnitude(_ v: Vec3) -> Float {
    max(abs(v.x), max(abs(v.y), abs(v.z)))
}

/// Rec. 709 luminance of a linear RGB value.
@inlinable @inline(__always)
func luminance(_ c: Vec3) -> Float {
    0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
}

@inlinable @inline(__always)
func isFinite(_ v: Vec3) -> Bool {
    v.x.isFinite && v.y.isFinite && v.z.isFinite
}

@inlinable @inline(__always)
func pow5(_ x: Float) -> Float {
    let x2 = x * x
    return x2 * x2 * x
}

/// Power heuristic (β = 2) for multiple importance sampling.
@inlinable @inline(__always)
func powerHeuristic(_ pdf: Float, _ otherPdf: Float) -> Float {
    let a = pdf * pdf
    let b = otherPdf * otherPdf
    let sum = a + b
    guard sum > 0, sum.isFinite else { return pdf.isInfinite ? 1 : 0 }
    return a / sum
}
