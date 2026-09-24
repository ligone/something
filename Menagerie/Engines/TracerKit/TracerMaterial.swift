import Foundation

/// A procedural color source.
public struct TracerTexture: Sendable, Hashable {
    public enum Pattern: Sendable, Hashable {
        /// A single color everywhere.
        case solid
        /// A checkerboard in the world XZ plane, made for floors.
        case checker
    }

    public var pattern: Pattern
    public var primary: TracerColor
    public var secondary: TracerColor
    /// Checker cell size in world units.
    public var cellSize: Float

    public static func solid(_ color: TracerColor) -> TracerTexture {
        TracerTexture(pattern: .solid, primary: color, secondary: color, cellSize: 1)
    }

    public static func checker(_ even: TracerColor, _ odd: TracerColor, cellSize: Float) -> TracerTexture {
        TracerTexture(pattern: .checker, primary: even, secondary: odd, cellSize: max(cellSize, 1e-4))
    }

    /// The texture's color at a world-space point.
    public func color(at point: SIMD3<Float>) -> TracerColor {
        switch pattern {
        case .solid:
            return primary
        case .checker:
            return Checker.isOdd(point, inverseCellSize: 1 / cellSize) ? secondary : primary
        }
    }
}

/// How a surface scatters or emits light.
///
/// Build materials with the static factories. Each maps onto a flat record
/// the render kernel can evaluate without dynamic dispatch.
public struct TracerMaterial: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// Ideal Lambertian reflector. It is sampled with cosine-weighted
        /// directions and receives next-event estimation.
        case diffuse
        /// Conductor with a Schlick-tinted reflectance and optional fuzz.
        case metal
        /// Smooth dielectric: exact refraction, Schlick Fresnel, total internal
        /// reflection and Beer–Lambert absorption.
        case glass
        /// A lacquered surface: a clear Fresnel coat over a diffuse base,
        /// like plastic, ceramic or a billiard ball.
        case glossy
        /// An area light. Quads emit from their front face only.
        case emissive
    }

    public var kind: Kind
    /// Base color: albedo for diffuse and glossy surfaces, reflectance at
    /// normal incidence for metals.
    public var texture: TracerTexture
    /// Metal fuzz or coat roughness, from 0 (mirror) to 1.
    public var roughness: Float
    public var indexOfRefraction: Float
    /// Glass color: the fraction of light surviving one world unit inside
    /// the medium.
    public var transmittance: TracerColor
    /// Emitted radiance for lights.
    public var emission: TracerColor

    public static func diffuse(_ color: TracerColor) -> TracerMaterial {
        diffuse(texture: .solid(color))
    }

    public static func diffuse(texture: TracerTexture) -> TracerMaterial {
        TracerMaterial(kind: .diffuse, texture: texture, roughness: 1, indexOfRefraction: 1,
                       transmittance: .one, emission: .zero)
    }

    public static func metal(_ color: TracerColor, fuzz: Float = 0) -> TracerMaterial {
        TracerMaterial(kind: .metal, texture: .solid(color), roughness: min(max(fuzz, 0), 1), indexOfRefraction: 1,
                       transmittance: .one, emission: .zero)
    }

    public static func glass(indexOfRefraction: Float = 1.5, transmittance: TracerColor = .one) -> TracerMaterial {
        TracerMaterial(kind: .glass, texture: .solid(.one), roughness: 0, indexOfRefraction: max(indexOfRefraction, 1e-3),
                       transmittance: transmittance, emission: .zero)
    }

    public static func glossy(_ color: TracerColor, roughness: Float = 0) -> TracerMaterial {
        glossy(texture: .solid(color), roughness: roughness)
    }

    public static func glossy(texture: TracerTexture, roughness: Float = 0) -> TracerMaterial {
        TracerMaterial(kind: .glossy, texture: texture, roughness: min(max(roughness, 0), 1), indexOfRefraction: 1.5,
                       transmittance: .one, emission: .zero)
    }

    public static func light(_ radiance: TracerColor) -> TracerMaterial {
        TracerMaterial(kind: .emissive, texture: .solid(.zero), roughness: 1, indexOfRefraction: 1,
                       transmittance: .one, emission: radiance)
    }
}
