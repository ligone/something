/// A ray with a unit-length direction.
public struct TracerRay: Sendable, Equatable {
    public var origin: SIMD3<Float>
    /// Always unit length: the initializer normalizes it.
    public private(set) var direction: SIMD3<Float>

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        self.direction = normalize(direction)
    }

    /// The point `distance` units along the ray.
    public func point(at distance: Float) -> SIMD3<Float> {
        origin + direction * distance
    }
}

/// Where a ray meets a surface.
public struct TracerHit: Sendable, Equatable {
    /// Distance along the ray, which equals the ray parameter `t` because
    /// ray directions are unit length.
    public var distance: Float
    public var point: SIMD3<Float>
    /// The unit geometric normal. For spheres it points outward. For quads it
    /// is `edgeU × edgeV`, and for planes it is the normal the plane was
    /// declared with.
    public var normal: SIMD3<Float>
    /// `true` when the ray arrived from the side the normal points to.
    public var isFrontFace: Bool
    /// The index of the object in `TracerScene.objects`, or `nil` when a
    /// standalone `TracerShape` was intersected.
    public var objectIndex: Int?

    public init(distance: Float, point: SIMD3<Float>, normal: SIMD3<Float>, isFrontFace: Bool, objectIndex: Int? = nil) {
        self.distance = distance
        self.point = point
        self.normal = normal
        self.isFrontFace = isFrontFace
        self.objectIndex = objectIndex
    }
}
