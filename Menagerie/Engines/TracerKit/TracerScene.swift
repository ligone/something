/// A named shape with a material.
public struct TracerObject: Sendable, Equatable {
    public var name: String
    public var shape: TracerShape
    public var material: TracerMaterial

    public init(_ name: String, shape: TracerShape, material: TracerMaterial) {
        self.name = name
        self.shape = shape
        self.material = material
    }
}

/// A complete, renderable description of a scene. It is a plain value, so
/// it is cheap to copy and edit. `TracerWorld` compiles it for rendering.
public struct TracerScene: Sendable, Equatable {
    public var name: String
    public var objects: [TracerObject]
    public var sky: TracerSky
    /// The framing the scene looks best from.
    public var camera: TracerCamera
    /// The aspect ratio `camera` was framed for. See
    /// `TracerCamera.framed(forAspectRatio:referenceAspectRatio:)`.
    public var referenceAspectRatio: Float
    /// How far an interactive orbit may stray from that framing.
    public var orbitLimits: TracerOrbitLimits
    /// Suggested exposure in stops (EV).
    public var exposure: Float
    /// Suggested maximum path length.
    public var maxBounces: Int

    public init(name: String, objects: [TracerObject] = [], sky: TracerSky = .black, camera: TracerCamera,
                referenceAspectRatio: Float = 1.5, orbitLimits: TracerOrbitLimits = TracerOrbitLimits(),
                exposure: Float = 0, maxBounces: Int = 8) {
        self.name = name
        self.objects = objects
        self.sky = sky
        self.camera = camera
        self.referenceAspectRatio = referenceAspectRatio
        self.orbitLimits = orbitLimits
        self.exposure = exposure
        self.maxBounces = maxBounces
    }

    public mutating func add(_ name: String, _ shape: TracerShape, _ material: TracerMaterial) {
        objects.append(TracerObject(name, shape: shape, material: material))
    }

    /// Adds the six faces of a box that share one name and material.
    public mutating func addBox(_ name: String, center: SIMD3<Float>, size: SIMD3<Float>, yawDegrees: Float = 0,
                                material: TracerMaterial) {
        for face in TracerShape.box(center: center, size: size, yawDegrees: yawDegrees) {
            add(name, face, material)
        }
    }
}
