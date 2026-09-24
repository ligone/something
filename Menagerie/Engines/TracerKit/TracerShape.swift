import Foundation

/// The geometric primitives TracerKit can trace.
public enum TracerShape: Sendable, Equatable {
    /// A sphere, the path tracer's workhorse.
    case sphere(center: SIMD3<Float>, radius: Float)
    /// A parallelogram spanned by two edges from a corner. Its normal is
    /// `edgeU × edgeV`. That side is the front, and an emissive quad lights
    /// only that side.
    case quad(corner: SIMD3<Float>, edgeU: SIMD3<Float>, edgeV: SIMD3<Float>)
    /// An infinite plane through `point`. It is kept out of the BVH because it
    /// has no finite bounds.
    case plane(point: SIMD3<Float>, normal: SIMD3<Float>)
}

extension TracerShape {
    /// Intersects a ray with this shape alone, returning the nearest hit with
    /// `tMin < distance < tMax`.
    public func intersect(_ ray: TracerRay, tMin: Float = 0, tMax: Float = .infinity) -> TracerHit? {
        let o = ray.origin
        let d = ray.direction
        switch self {
        case let .sphere(center, radius):
            let t = Intersect.sphere(center: center, radius: radius, origin: o, direction: d, tMin: tMin, tMax: tMax)
            guard t < tMax else { return nil }
            let point = o + d * t
            let normal = (point - center) * (1 / radius)
            return TracerHit(distance: t, point: point, normal: normal, isFrontFace: dot(d, normal) < 0)
        case let .quad(corner, edgeU, edgeV):
            let frame = QuadFrame(corner: corner, edgeU: edgeU, edgeV: edgeV)
            guard frame.isValid else { return nil }
            let t = Intersect.quad(corner: frame.corner, edgeU: frame.edgeU, edgeV: frame.edgeV, normal: frame.normal,
                                   w: frame.w, offset: frame.offset, origin: o, direction: d, tMin: tMin, tMax: tMax)
            guard t < tMax else { return nil }
            return TracerHit(distance: t, point: o + d * t, normal: frame.normal, isFrontFace: dot(d, frame.normal) < 0)
        case let .plane(point, normal):
            let n = normalize(normal)
            let t = Intersect.plane(normal: n, offset: dot(n, point), origin: o, direction: d, tMin: tMin, tMax: tMax)
            guard t < tMax else { return nil }
            return TracerHit(distance: t, point: o + d * t, normal: n, isFrontFace: dot(d, n) < 0)
        }
    }

    /// Surface area in square world units. It is infinite for planes.
    public var area: Float {
        switch self {
        case let .sphere(_, radius):
            return 4 * Float.pi * radius * radius
        case let .quad(_, edgeU, edgeV):
            return length(cross(edgeU, edgeV))
        case .plane:
            return .infinity
        }
    }

    /// Axis-aligned bounds, or `nil` for unbounded shapes.
    var bounds: (lower: SIMD3<Float>, upper: SIMD3<Float>)? {
        switch self {
        case let .sphere(center, radius):
            let r = SIMD3<Float>(repeating: abs(radius))
            return (center - r, center + r)
        case let .quad(corner, edgeU, edgeV):
            let points = [corner, corner + edgeU, corner + edgeV, corner + edgeU + edgeV]
            var lower = points[0]
            var upper = points[0]
            for p in points.dropFirst() {
                lower = pointwiseMin(lower, p)
                upper = pointwiseMax(upper, p)
            }
            // Pad flat, axis-aligned quads so their boxes keep some thickness.
            let pad = SIMD3<Float>(repeating: 1e-4 * (1 + max(maxMagnitude(lower), maxMagnitude(upper))))
            return (lower - pad, upper + pad)
        case .plane:
            return nil
        }
    }

    /// The six outward-facing quads of a box resting in the scene. The box is
    /// centered at `center`, and `yawDegrees` turns it about its vertical axis,
    /// counterclockwise when seen from above.
    public static func box(center: SIMD3<Float>, size: SIMD3<Float>, yawDegrees: Float = 0) -> [TracerShape] {
        let angle = yawDegrees * Float.pi / 180
        let c = cos(angle)
        let s = sin(angle)
        func turn(_ v: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3<Float>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z)
        }
        let dx = turn(SIMD3<Float>(size.x, 0, 0))
        let dy = SIMD3<Float>(0, size.y, 0)
        let dz = turn(SIMD3<Float>(0, 0, size.z))
        let origin = center - (dx + dy + dz) * 0.5
        return [
            .quad(corner: origin + dz, edgeU: dx, edgeV: dy),  // front, +Z
            .quad(corner: origin, edgeU: dy, edgeV: dx),       // back, −Z
            .quad(corner: origin + dx, edgeU: dy, edgeV: dz),  // right, +X
            .quad(corner: origin, edgeU: dz, edgeV: dy),       // left, −X
            .quad(corner: origin + dy, edgeU: dz, edgeV: dx),  // top, +Y
            .quad(corner: origin, edgeU: dx, edgeV: dz),       // bottom, −Y
        ]
    }
}

/// Precomputed plane data for a parallelogram, as used by `Intersect.quad`.
struct QuadFrame {
    let corner: Vec3
    let edgeU: Vec3
    let edgeV: Vec3
    /// Unit normal, `normalize(edgeU × edgeV)`.
    let normal: Vec3
    /// `n / (n · n)` for the unnormalized normal `n`. It turns cross products
    /// into planar coordinates.
    let w: Vec3
    /// Plane offset, `normal · corner`.
    let offset: Float
    let area: Float

    init(corner: Vec3, edgeU: Vec3, edgeV: Vec3) {
        let n = cross(edgeU, edgeV)
        let nn = dot(n, n)
        self.corner = corner
        self.edgeU = edgeU
        self.edgeV = edgeV
        self.area = nn.squareRoot()
        self.normal = nn > 0 ? n * (1 / nn.squareRoot()) : .zero
        self.w = nn > 0 ? n * (1 / nn) : .zero
        self.offset = dot(normal, corner)
    }

    var isValid: Bool { area > 0 }
}
