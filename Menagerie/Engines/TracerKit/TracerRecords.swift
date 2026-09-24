import Foundation

// Flat, reference-free records: the compiled scene as the render kernel sees
// it. `TracerWorld` builds them from the public scene types. The small methods
// the inner loop calls on them live in TracerKernel.swift, next to their
// callers, so they inline even without whole-module optimization.

enum MaterialKind: UInt8 {
    case diffuse, metal, glass, glossy, emissive
}

struct MaterialRecord {
    let kind: MaterialKind
    let isChecker: Bool
    let colorA: Vec3
    let colorB: Vec3
    let inverseCellSize: Float
    let roughness: Float
    let indexOfRefraction: Float
    /// Beer–Lambert absorption coefficient, `−ln(transmittance)`.
    let absorption: Vec3
    let hasAbsorption: Bool
    let emission: Vec3

    init(_ material: TracerMaterial) {
        switch material.kind {
        case .diffuse: kind = .diffuse
        case .metal: kind = .metal
        case .glass: kind = .glass
        case .glossy: kind = .glossy
        case .emissive: kind = .emissive
        }
        isChecker = material.texture.pattern == .checker
        colorA = material.texture.primary
        colorB = material.texture.secondary
        inverseCellSize = 1 / material.texture.cellSize
        roughness = material.roughness
        indexOfRefraction = material.indexOfRefraction
        let t = pointwiseMin(pointwiseMax(material.transmittance, Vec3(repeating: 1e-6)), Vec3(repeating: 1))
        absorption = Vec3(-log(t.x), -log(t.y), -log(t.z))
        hasAbsorption = maxComponent(absorption) > 0
        emission = material.emission
    }
}

/// A bounded primitive. Spheres use `a` as the center and `scalar` as the
/// signed radius, and a negative radius flips the normals to make a hollow
/// bubble. Quads use `a`, `b` and `c` as corner and edges, `normal` and `w`
/// for the plane, and `scalar` as the plane offset.
struct PrimitiveRecord {
    let a: Vec3
    let b: Vec3
    let c: Vec3
    let normal: Vec3
    let w: Vec3
    let scalar: Float
    let isSphere: Bool
    let material: Int32
    let light: Int32
    let object: Int32

    init(sphereCenter: Vec3, radius: Float, material: Int32, object: Int32) {
        a = sphereCenter
        b = .zero
        c = .zero
        normal = .zero
        w = .zero
        scalar = radius
        isSphere = true
        self.material = material
        light = -1
        self.object = object
    }

    init(quad: QuadFrame, material: Int32, light: Int32, object: Int32) {
        a = quad.corner
        b = quad.edgeU
        c = quad.edgeV
        normal = quad.normal
        w = quad.w
        scalar = quad.offset
        isSphere = false
        self.material = material
        self.light = light
        self.object = object
    }
}

struct PlaneRecord {
    let normal: Vec3
    let offset: Float
    let material: Int32
    let object: Int32
}

/// An emissive quad that next-event estimation can sample.
struct LightRecord {
    let corner: Vec3
    let edgeU: Vec3
    let edgeV: Vec3
    let normal: Vec3
    let radiance: Vec3
    let area: Float
    /// Probability of choosing this light, proportional to its power.
    var selectionPdf: Float = 0
    /// Running sum of `selectionPdf`, used for sampling by inversion.
    var cumulative: Float = 0

    init(frame: QuadFrame, radiance: Vec3) {
        corner = frame.corner
        edgeU = frame.edgeU
        edgeV = frame.edgeV
        normal = frame.normal
        self.radiance = radiance
        area = frame.area
    }

    static func assignSelectionProbabilities(_ lights: inout [LightRecord]) {
        let powers = lights.map { max(luminance($0.radiance) * $0.area, 1e-12) }
        let total = powers.reduce(0, +)
        var running: Float = 0
        for i in lights.indices {
            lights[i].selectionPdf = powers[i] / total
            running += lights[i].selectionPdf
            lights[i].cumulative = running
        }
        if !lights.isEmpty { lights[lights.count - 1].cumulative = 1 }
    }
}

/// The kernel's flattened view of the sky.
struct SkyRecord {
    let zenith: Vec3
    let horizon: Vec3
    let ground: Vec3
    let hasSun: Bool
    let sunDirection: Vec3
    let sunRadiance: Vec3
    let sunCosMax: Float
    /// Solid-angle density of uniform cone sampling, `1 / Ω`.
    let sunPdf: Float
    let sunFrame: LocalFrame

    init(_ sky: TracerSky) {
        zenith = sky.zenith
        horizon = sky.horizon
        ground = sky.ground
        if let sun = sky.sun, maxComponent(sun.radiance) > 0 {
            hasSun = true
            sunDirection = sun.direction
            sunRadiance = sun.radiance
            sunCosMax = sun.cosAngularRadius
            sunPdf = 1 / sun.solidAngle
            sunFrame = LocalFrame(normal: sun.direction)
        } else {
            hasSun = false
            sunDirection = Vec3(0, 1, 0)
            sunRadiance = .zero
            sunCosMax = 1
            sunPdf = 0
            sunFrame = LocalFrame(normal: Vec3(0, 1, 0))
        }
    }
}

struct SurfaceHit {
    var t: Float = .infinity
    var point: Vec3 = .zero
    /// Unit geometric normal (outward for spheres).
    var normal: Vec3 = .zero
    var frontFace = true
    var material: Int32 = 0
    var light: Int32 = -1
    var object: Int32 = -1
}
