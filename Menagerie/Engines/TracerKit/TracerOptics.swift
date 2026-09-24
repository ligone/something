/// Reflection, refraction and Fresnel helpers. The render kernel uses these
/// same functions for glass, so testing them tests the renderer.
public enum TracerOptics {
    /// Mirror reflection of `incident` about the unit `normal`.
    @inlinable @inline(__always)
    public static func reflect(_ incident: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float> {
        incident - normal * (2 * dot(incident, normal))
    }

    /// Refracts the unit direction `incident` by Snell's law.
    ///
    /// - Parameters:
    ///   - normal: The unit normal on the side the ray arrives from, so that
    ///     `dot(incident, normal) <= 0`.
    ///   - eta: The ratio of refractive indices, `n₁ / n₂`.
    /// - Returns: The unit transmitted direction, or `nil` when the ray is
    ///   totally internally reflected.
    @inlinable @inline(__always)
    public static func refract(_ incident: SIMD3<Float>, normal: SIMD3<Float>, eta: Float) -> SIMD3<Float>? {
        let cosIncident = min(max(-dot(incident, normal), 0), 1)
        let sin2Transmitted = eta * eta * (1 - cosIncident * cosIncident)
        if sin2Transmitted > 1 { return nil }
        let cosTransmitted = (1 - sin2Transmitted).squareRoot()
        return normalize(incident * eta + normal * (eta * cosIncident - cosTransmitted))
    }

    /// Schlick's approximation of the Fresnel reflectance of a dielectric
    /// boundary, going from index `n1` into index `n2`.
    ///
    /// Returns 1 beyond the critical angle (total internal reflection). When
    /// leaving the denser medium, the formula uses the cosine of the
    /// transmitted angle, which keeps Schlick's approximation accurate on
    /// that side as well.
    @inlinable @inline(__always)
    public static func schlickReflectance(cosIncident: Float, n1: Float, n2: Float) -> Float {
        if n1 == n2 { return 0 }  // index-matched media have no interface
        let cosI = min(max(cosIncident, 0), 1)
        let eta = n1 / n2
        let sin2T = eta * eta * (1 - cosI * cosI)
        if sin2T >= 1 { return 1 }
        let r = (n1 - n2) / (n1 + n2)
        let r0 = r * r
        let cosine = n1 > n2 ? (1 - sin2T).squareRoot() : cosI
        return r0 + (1 - r0) * pow5(1 - cosine)
    }

    /// The exact unpolarized Fresnel reflectance of a dielectric boundary,
    /// averaging the s- and p-polarized terms.
    public static func exactReflectance(cosIncident: Float, n1: Float, n2: Float) -> Float {
        if n1 == n2 { return 0 }
        let cosI = min(max(cosIncident, 0), 1)
        let eta = n1 / n2
        let sin2T = eta * eta * (1 - cosI * cosI)
        if sin2T >= 1 { return 1 }
        let cosT = (1 - sin2T).squareRoot()
        let rs = (n1 * cosI - n2 * cosT) / (n1 * cosI + n2 * cosT)
        let rp = (n2 * cosI - n1 * cosT) / (n2 * cosI + n1 * cosT)
        return 0.5 * (rs * rs + rp * rp)
    }
}
