import Foundation

/// Turns scene-referred linear radiance into display-ready sRGB.
///
/// The pipeline is exposure (in stops), then an ACES filmic curve, then the
/// sRGB transfer function. The curve is Stephen Hill's fit of the ACES RRT
/// and ODT, which wraps the tone curve in color matrices, so bright saturated
/// light desaturates gracefully toward white instead of clipping to a hue.
public enum TracerToneMapper {
    /// Linear exposure scale for an exposure in stops.
    public static func exposureScale(_ stops: Float) -> Float {
        exp2(stops)
    }

    /// The ACES filmic fit. Input is linear Rec. 709 RGB, and output is
    /// display-linear RGB clamped to `0...1`. Negative and NaN input maps to 0.
    @inline(__always)
    public static func acesFilmic(_ color: TracerColor) -> TracerColor {
        let c = TracerColor(clampPositive(color.x), clampPositive(color.y), clampPositive(color.z))
        // sRGB → ACES AP1, including the RRT saturation tweak.
        let a = TracerColor(
            0.59719 * c.x + 0.35458 * c.y + 0.04823 * c.z,
            0.07600 * c.x + 0.90834 * c.y + 0.01566 * c.z,
            0.02840 * c.x + 0.13383 * c.y + 0.83777 * c.z
        )
        let numerator = a * (a + 0.024_578_6) - 0.000_090_537
        let denominator = a * (a * 0.983_729 + 0.432_951_0) + 0.238_081
        let fitted = numerator / denominator
        // ODT saturation → sRGB.
        let out = TracerColor(
            1.60475 * fitted.x - 0.53108 * fitted.y - 0.07367 * fitted.z,
            -0.10208 * fitted.x + 1.10813 * fitted.y - 0.00605 * fitted.z,
            -0.00327 * fitted.x - 0.07276 * fitted.y + 1.07602 * fitted.z
        )
        return TracerColor(clampUnit(out.x), clampUnit(out.y), clampUnit(out.z))
    }

    /// The sRGB opto-electronic transfer function (IEC 61966-2-1).
    public static func encodeSRGB(_ linear: Float) -> Float {
        let v = clampUnit(linear)
        return v <= 0.003_130_8 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// Maps one linear color to 8-bit sRGB without dithering.
    public static func displayColor(_ linear: TracerColor, exposure: Float) -> SIMD3<UInt8> {
        let mapped = acesFilmic(linear * exposureScale(exposure))
        return SIMD3<UInt8>(quantize(encodeSRGB(mapped.x)), quantize(encodeSRGB(mapped.y)), quantize(encodeSRGB(mapped.z)))
    }

    /// Tone-maps one row of summed radiance into RGBA8.
    ///
    /// - Parameters:
    ///   - sums: `width` RGB triples of accumulated radiance.
    ///   - scale: Exposure scale divided by the row's sample count.
    ///   - y: The row index, which seeds the dither pattern.
    ///   - output: Room for `width` RGBA pixels.
    static func encodeRow(_ sums: UnsafePointer<Float>, width: Int, scale: Float, y: Int,
                          table: UnsafeBufferPointer<Float>, into output: UnsafeMutablePointer<UInt8>) {
        let lastIndex = Float(table.count - 1)
        for x in 0..<width {
            let i = x * 3
            let mapped = acesFilmic(TracerColor(sums[i], sums[i + 1], sums[i + 2]) * scale)
            // A fixed per-pixel dither of ±½ LSB hides banding in smooth
            // gradients, such as the sky and soft shadows.
            let hash = ditherHash(x, y)
            let d0 = Float(hash & 0x3FF) * (1 / 1024) - 0.5
            let d1 = Float((hash &>> 10) & 0x3FF) * (1 / 1024) - 0.5
            let d2 = Float((hash &>> 20) & 0x3FF) * (1 / 1024) - 0.5
            let o = x * 4
            output[o] = byte(table[Int(mapped.x * lastIndex + 0.5)] + d0)
            output[o + 1] = byte(table[Int(mapped.y * lastIndex + 0.5)] + d1)
            output[o + 2] = byte(table[Int(mapped.z * lastIndex + 0.5)] + d2)
            output[o + 3] = 255
        }
    }

    /// sRGB-encoded values scaled to 0...255, indexed by display-linear value.
    /// This replaces a `pow` per channel in the snapshot loop.
    static let encodingTable: [Float] = (0..<8192).map { index in
        encodeSRGB(Float(index) / 8191) * 255
    }

    @inline(__always)
    static func clampUnit(_ v: Float) -> Float {
        // `maximum` and `minimum` return the non-NaN operand, so NaN maps to 0.
        Float.minimum(Float.maximum(v, 0), 1)
    }

    /// Clamps curve input to `0...1e6`. NaN becomes 0. The curve has fully
    /// saturated long before 1e6, and the cap keeps its rational terms from
    /// overflowing.
    @inline(__always)
    static func clampPositive(_ v: Float) -> Float {
        v > 0 ? Float.minimum(v, 1e6) : 0
    }

    @inline(__always)
    static func quantize(_ encoded: Float) -> UInt8 {
        byte(encoded * 255)
    }

    @inline(__always)
    static func byte(_ level: Float) -> UInt8 {
        UInt8(Float.minimum(Float.maximum(level + 0.5, 0), 255.99))
    }

    /// A 32-bit hash of a pixel coordinate (lowbias32 by Chris Wellons).
    @inline(__always)
    static func ditherHash(_ x: Int, _ y: Int) -> UInt32 {
        var h = (UInt32(truncatingIfNeeded: x) &* 0x9E37_79B1) ^ (UInt32(truncatingIfNeeded: y) &* 0x85EB_CA77)
        h ^= h &>> 16
        h = h &* 0x7FEB_352D
        h ^= h &>> 15
        h = h &* 0x846C_A68B
        h ^= h &>> 16
        return h
    }
}
