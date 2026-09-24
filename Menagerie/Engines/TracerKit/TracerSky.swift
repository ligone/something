import Foundation

/// A distant disk light. The integrator samples it directly (next-event
/// estimation) and weights it against BSDF sampling with MIS, so soft sun
/// shadows converge quickly.
public struct TracerSun: Sendable, Equatable {
    /// Unit vector pointing from the scene toward the sun.
    public var direction: SIMD3<Float>
    /// Angular radius in degrees. The real sun is about 0.27°. Larger values
    /// soften shadows.
    public var angularRadius: Float
    /// Radiance of the disk.
    public var radiance: TracerColor

    public init(direction: SIMD3<Float>, angularRadius: Float, radiance: TracerColor) {
        self.direction = normalize(direction)
        self.angularRadius = min(max(angularRadius, 0.05), 45)
        self.radiance = radiance
    }

    var cosAngularRadius: Float { cos(angularRadius * Float.pi / 180) }
    var solidAngle: Float { 2 * Float.pi * (1 - cosAngularRadius) }
}

/// The environment seen by rays that leave the scene: a vertical gradient
/// from ground through horizon to zenith, plus an optional sun.
public struct TracerSky: Sendable, Equatable {
    public var zenith: TracerColor
    public var horizon: TracerColor
    public var ground: TracerColor
    public var sun: TracerSun?

    public init(zenith: TracerColor, horizon: TracerColor, ground: TracerColor, sun: TracerSun? = nil) {
        self.zenith = zenith
        self.horizon = horizon
        self.ground = ground
        self.sun = sun
    }

    /// A black void, for scenes lit only by their own lights.
    public static let black = TracerSky(zenith: .zero, horizon: .zero, ground: .zero)

    /// The same radiance in every direction. A diffuse white object inside it
    /// should vanish, which makes it the classic "white furnace" test.
    public static func uniform(_ radiance: TracerColor) -> TracerSky {
        TracerSky(zenith: radiance, horizon: radiance, ground: radiance)
    }

    /// Radiance arriving from `direction`, including the sun disk.
    public func radiance(toward direction: SIMD3<Float>) -> TracerColor {
        let d = normalize(direction)
        var value = SkyRecord.gradient(d, zenith: zenith, horizon: horizon, ground: ground)
        if let sun, dot(d, sun.direction) >= sun.cosAngularRadius {
            value += sun.radiance
        }
        return value
    }
}
