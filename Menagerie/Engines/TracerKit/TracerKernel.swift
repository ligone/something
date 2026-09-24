import Foundation

// The render kernel: every function the per-sample inner loop calls.
//
// They live in one file on purpose. Debug builds compile the engine with
// `-O` but without whole-module optimization, and then the optimizer can only
// inline code from the same file. Keeping random numbers, sampling,
// intersection, BVH traversal and the integrator together makes the kernel
// equally fast in either build mode. The data they operate on, the flat
// records in TracerRecords.swift, can live elsewhere, because reading a
// stored property never needs a call.

// MARK: - Random numbers

/// A small, fast PCG32 generator (O'Neill, "PCG: A Family of Simple Fast
/// Space-Efficient Statistically Good Algorithms for Random Number Generation").
///
/// The renderer creates one per image row per sample index, seeded by hashing
/// the render seed, the row and the sample index. Every pixel's random stream is
/// therefore fixed however the rows are scheduled across threads, which keeps
/// renders reproducible.
struct TracerRNG {
    private var state: UInt64
    private let increment: UInt64

    @inline(__always)
    init(seed: UInt64, stream: UInt64) {
        state = 0
        increment = (stream &<< 1) | 1
        _ = nextUInt32()
        state = state &+ seed
        _ = nextUInt32()
    }

    /// A generator for one image row of one progressive sample.
    @inline(__always)
    init(seed: UInt64, row: Int, sample: Int) {
        let rowKey = Hash.mix64(UInt64(truncatingIfNeeded: row) &+ 0x632B_E59B_D9B4_E019)
        self.init(seed: Hash.mix64(seed ^ rowKey), stream: UInt64(truncatingIfNeeded: sample))
    }

    @inline(__always)
    mutating func nextUInt32() -> UInt32 {
        let old = state
        state = old &* 6_364_136_223_846_793_005 &+ increment
        let xorShifted = UInt32(truncatingIfNeeded: ((old &>> 18) ^ old) &>> 27)
        let rotation = UInt32(truncatingIfNeeded: old &>> 59)
        return (xorShifted &>> rotation) | (xorShifted &<< ((0 &- rotation) & 31))
    }

    /// A uniform float in `[0, 1)` with 24 bits of precision.
    @inline(__always)
    mutating func nextFloat() -> Float {
        Float(nextUInt32() &>> 8) * 0x1p-24
    }
}

enum Hash {
    /// The SplitMix64 finalizer: a strong 64-bit integer mix.
    @inline(__always)
    static func mix64(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}

// MARK: - Sampling

/// Warps uniform random numbers into the distributions the integrator needs.
enum Sampling {
    /// A cosine-weighted direction on the +Z hemisphere (Malley's method).
    /// Its density is `cos θ / π`.
    @inline(__always)
    static func cosineHemisphere(_ u1: Float, _ u2: Float) -> Vec3 {
        let radius = u1.squareRoot()
        let phi = 2 * Float.pi * u2
        let z = max(0, 1 - u1).squareRoot()
        return Vec3(radius * cos(phi), radius * sin(phi), z)
    }

    /// A uniformly distributed unit vector.
    @inline(__always)
    static func unitSphere(_ u1: Float, _ u2: Float) -> Vec3 {
        let z = 1 - 2 * u1
        let radius = max(0, 1 - z * z).squareRoot()
        let phi = 2 * Float.pi * u2
        return Vec3(radius * cos(phi), radius * sin(phi), z)
    }

    /// A uniform point on the unit disk, using Shirley and Chiu's concentric
    /// mapping, which preserves stratification and gives round bokeh.
    @inline(__always)
    static func concentricDisk(_ u1: Float, _ u2: Float) -> SIMD2<Float> {
        let a = 2 * u1 - 1
        let b = 2 * u2 - 1
        if a == 0 && b == 0 { return .zero }
        let radius: Float
        let phi: Float
        if abs(a) > abs(b) {
            radius = a
            phi = (Float.pi / 4) * (b / a)
        } else {
            radius = b
            phi = Float.pi / 2 - (Float.pi / 4) * (a / b)
        }
        return SIMD2<Float>(radius * cos(phi), radius * sin(phi))
    }

    /// A uniform direction inside a cone of half-angle `acos(cosThetaMax)`
    /// around +Z. Its density is `1 / (2π (1 − cosThetaMax))`.
    @inline(__always)
    static func uniformCone(_ u1: Float, _ u2: Float, cosThetaMax: Float) -> Vec3 {
        let cosTheta = 1 - u1 * (1 - cosThetaMax)
        let sinTheta = max(0, 1 - cosTheta * cosTheta).squareRoot()
        let phi = 2 * Float.pi * u2
        return Vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta)
    }
}

/// An orthonormal basis around a unit normal. It maps samples generated in a
/// local frame, where +Z is the normal, into world space.
struct LocalFrame {
    let tangent: Vec3
    let bitangent: Vec3
    let normal: Vec3

    /// Branchless construction from Duff et al., "Building an Orthonormal
    /// Basis, Revisited" (JCGT 2017).
    @inline(__always)
    init(normal n: Vec3) {
        let sign: Float = n.z >= 0 ? 1 : -1
        let a = -1 / (sign + n.z)
        let b = n.x * n.y * a
        tangent = Vec3(1 + sign * n.x * n.x * a, sign * b, -sign * n.x)
        bitangent = Vec3(b, sign + n.y * n.y * a, -n.y)
        normal = n
    }

    @inline(__always)
    func toWorld(_ local: Vec3) -> Vec3 {
        tangent * local.x + bitangent * local.y + normal * local.z
    }
}

// MARK: - Ray–primitive intersection

/// Ray–primitive intersection routines shared by the public API and the
/// render kernel. Directions must be unit length. Each routine returns the hit
/// distance, or `.infinity` on a miss.
enum Intersect {
    /// A numerically robust ray–sphere test (Haines et al., *Ray Tracing
    /// Gems*, chapter 7). It measures the discriminant from the closest-approach
    /// vector instead of subtracting two large squares.
    @inline(__always)
    static func sphere(center: Vec3, radius: Float, origin: Vec3, direction: Vec3, tMin: Float, tMax: Float) -> Float {
        let toCenter = center - origin
        let b = dot(toCenter, direction)
        let perpendicular = toCenter - direction * b
        let h2 = radius * radius - dot(perpendicular, perpendicular)
        if h2 < 0 { return .infinity }
        let h = h2.squareRoot()
        let near = b - h
        if near > tMin && near < tMax { return near }
        let far = b + h
        if far > tMin && far < tMax { return far }
        return .infinity
    }

    /// Ray–parallelogram test using planar coordinates, following *Ray
    /// Tracing: The Next Week*. The edges are inclusive, so rays through the
    /// border or a corner count as hits.
    @inline(__always)
    static func quad(corner: Vec3, edgeU: Vec3, edgeV: Vec3, normal: Vec3, w: Vec3, offset: Float,
                     origin: Vec3, direction: Vec3, tMin: Float, tMax: Float) -> Float {
        let denominator = dot(normal, direction)
        if abs(denominator) < 1e-9 { return .infinity }
        let t = (offset - dot(normal, origin)) / denominator
        if !(t > tMin && t < tMax) { return .infinity }
        let planar = origin + direction * t - corner
        let alpha = dot(w, cross(planar, edgeV))
        if alpha < 0 || alpha > 1 { return .infinity }
        let beta = dot(w, cross(edgeU, planar))
        if beta < 0 || beta > 1 { return .infinity }
        return t
    }

    /// Ray–plane test for a plane `normal · p = offset`.
    @inline(__always)
    static func plane(normal: Vec3, offset: Float, origin: Vec3, direction: Vec3, tMin: Float, tMax: Float) -> Float {
        let denominator = dot(normal, direction)
        if abs(denominator) < 1e-9 { return .infinity }
        let t = (offset - dot(normal, origin)) / denominator
        return (t > tMin && t < tMax) ? t : .infinity
    }
}

// MARK: - Shading helpers

enum Checker {
    /// Checker parity computed entirely in floating point, so far-away hits
    /// with huge coordinates can't overflow an integer conversion.
    @inline(__always)
    static func isOdd(_ p: Vec3, inverseCellSize: Float) -> Bool {
        let sum = (p.x * inverseCellSize).rounded(.down) + (p.z * inverseCellSize).rounded(.down)
        let half = sum * 0.5
        return half != half.rounded(.down)
    }
}

extension MaterialRecord {
    @inline(__always)
    func albedo(at point: Vec3) -> Vec3 {
        guard isChecker else { return colorA }
        return Checker.isOdd(point, inverseCellSize: inverseCellSize) ? colorB : colorA
    }
}

extension SkyRecord {
    /// The gradient without the sun disk.
    @inline(__always)
    func background(_ d: Vec3) -> Vec3 {
        SkyRecord.gradient(d, zenith: zenith, horizon: horizon, ground: ground)
    }

    @inline(__always)
    static func gradient(_ d: Vec3, zenith: Vec3, horizon: Vec3, ground: Vec3) -> Vec3 {
        let y = d.y
        if y >= 0 {
            // A square-root ramp keeps a bright band near the horizon and
            // saturates toward the zenith, like a clear sky.
            return horizon + (zenith - horizon) * min(y, 1).squareRoot()
        }
        let t = min(-y * 5, 1)
        return horizon + (ground - horizon) * t
    }

    @inline(__always)
    func sunContains(_ d: Vec3) -> Bool {
        hasSun && dot(d, sunDirection) >= sunCosMax
    }
}

// MARK: - World traversal

/// A read-only, reference-free view of a `TracerWorld` for the render kernel.
/// The pointers refer to storage the world never mutates after it's built,
/// so any number of threads may share the view.
struct WorldKernel: @unchecked Sendable {
    let nodes: UnsafePointer<BVHNode>
    let nodeCount: Int
    let primitives: UnsafePointer<PrimitiveRecord>
    let planes: UnsafePointer<PlaneRecord>
    let planeCount: Int
    let materials: UnsafePointer<MaterialRecord>
    let lights: UnsafePointer<LightRecord>
    let lightCount: Int
    let sky: SkyRecord

    @inline(__always)
    func intersect(_ p: PrimitiveRecord, origin: Vec3, direction: Vec3, tMax: Float) -> Float {
        if p.isSphere {
            return Intersect.sphere(center: p.a, radius: p.scalar, origin: origin, direction: direction, tMin: 0, tMax: tMax)
        }
        return Intersect.quad(corner: p.a, edgeU: p.b, edgeV: p.c, normal: p.normal, w: p.w, offset: p.scalar,
                              origin: origin, direction: direction, tMin: 0, tMax: tMax)
    }

    /// Finds the nearest surface in `(0, tMax)` and fills `hit`.
    @inline(__always)
    func closestHit(origin: Vec3, direction: Vec3, tMax: Float, hit: inout SurfaceHit) -> Bool {
        var closest = tMax
        var plane = -1
        for i in 0..<planeCount {
            let t = Intersect.plane(normal: planes[i].normal, offset: planes[i].offset,
                                    origin: origin, direction: direction, tMin: 0, tMax: closest)
            if t < closest {
                closest = t
                plane = i
            }
        }
        let primitive = traverseClosest(origin: origin, direction: direction, tMax: &closest)

        let point = origin + direction * closest
        if primitive >= 0 {
            let p = primitives[primitive]
            hit.normal = p.isSphere ? (point - p.a) * (1 / p.scalar) : p.normal
            hit.material = p.material
            hit.light = p.light
            hit.object = p.object
        } else if plane >= 0 {
            let p = planes[plane]
            hit.normal = p.normal
            hit.material = p.material
            hit.light = -1
            hit.object = p.object
        } else {
            return false
        }
        hit.t = closest
        hit.point = point
        hit.frontFace = dot(direction, hit.normal) < 0
        return true
    }

    /// `true` if anything blocks the open segment `(0, tMax)`.
    @inline(__always)
    func occluded(origin: Vec3, direction: Vec3, tMax: Float) -> Bool {
        for i in 0..<planeCount {
            let t = Intersect.plane(normal: planes[i].normal, offset: planes[i].offset,
                                    origin: origin, direction: direction, tMin: 0, tMax: tMax)
            if t < tMax { return true }
        }
        return traverseAny(origin: origin, direction: direction, tMax: tMax)
    }

    /// Slab test against a node's box, limited to `(0, tMax)`.
    @inline(__always)
    func overlaps(_ node: BVHNode, origin: Vec3, inverseDirection: Vec3, tMax: Float) -> Bool {
        let t0 = (node.lower - origin) * inverseDirection
        let t1 = (node.upper - origin) * inverseDirection
        let near = pointwiseMin(t0, t1)
        let far = pointwiseMax(t0, t1)
        let enter = max(max(near.x, near.y), max(near.z, 0))
        let exit = min(min(far.x, far.y), min(far.z, tMax))
        return enter <= exit
    }

    /// Walks the BVH front to back. It returns the nearest primitive index
    /// hit before `tMax`, or −1, and narrows `tMax` to that hit's distance.
    @inline(__always)
    func traverseClosest(origin: Vec3, direction: Vec3, tMax: inout Float) -> Int {
        guard nodeCount > 0 else { return -1 }
        let inverse = Vec3(1 / direction.x, 1 / direction.y, 1 / direction.z)
        let negative = (direction.x < 0, direction.y < 0, direction.z < 0)
        var closest = tMax
        var found = -1
        // The builder caps tree depth at 48, so 64 stack slots always suffice.
        withUnsafeTemporaryAllocation(of: Int32.self, capacity: 64) { stack in
            var top = 0
            var index = 0
            while true {
                let node = nodes[index]
                if overlaps(node, origin: origin, inverseDirection: inverse, tMax: closest) {
                    if node.count > 0 {
                        let first = Int(node.offset)
                        for i in first..<(first + Int(node.count)) {
                            let t = intersect(primitives[i], origin: origin, direction: direction, tMax: closest)
                            if t < closest {
                                closest = t
                                found = i
                            }
                        }
                    } else {
                        // Visit the child on the ray's near side first so
                        // `closest` shrinks early and prunes the far side.
                        let flip: Bool
                        switch node.axis {
                        case 0: flip = negative.0
                        case 1: flip = negative.1
                        default: flip = negative.2
                        }
                        if flip {
                            stack[top] = Int32(index + 1)
                            index = Int(node.offset)
                        } else {
                            stack[top] = node.offset
                            index += 1
                        }
                        top += 1
                        continue
                    }
                }
                if top == 0 { break }
                top -= 1
                index = Int(stack[top])
            }
        }
        tMax = closest
        return found
    }

    /// Returns `true` as soon as any primitive blocks the segment `(0, tMax)`.
    @inline(__always)
    func traverseAny(origin: Vec3, direction: Vec3, tMax: Float) -> Bool {
        guard nodeCount > 0 else { return false }
        let inverse = Vec3(1 / direction.x, 1 / direction.y, 1 / direction.z)
        return withUnsafeTemporaryAllocation(of: Int32.self, capacity: 64) { stack -> Bool in
            var top = 0
            var index = 0
            while true {
                let node = nodes[index]
                if overlaps(node, origin: origin, inverseDirection: inverse, tMax: tMax) {
                    if node.count > 0 {
                        let first = Int(node.offset)
                        for i in first..<(first + Int(node.count))
                        where intersect(primitives[i], origin: origin, direction: direction, tMax: tMax) < tMax {
                            return true
                        }
                    } else {
                        stack[top] = node.offset
                        top += 1
                        index += 1
                        continue
                    }
                }
                if top == 0 { return false }
                top -= 1
                index = Int(stack[top])
            }
        }
    }
}

// MARK: - Path integrator

/// The path-tracing kernel: estimates the radiance arriving along one ray.
///
/// The integrator is iterative, not recursive. At each vertex it:
/// - adds emission, weighted by multiple importance sampling (MIS) whenever
///   next-event estimation could also have found that light;
/// - for diffuse lobes, samples one quad light (chosen in proportion to its
///   power) and the sun with shadow rays, weighted by the power heuristic;
/// - samples the BSDF to continue the path;
/// - applies Russian roulette after a few bounces.
struct PathKernel {
    let world: WorldKernel
    let maxBounces: Int
    let rouletteDepth: Int
    let clamp: Float
    /// Relative ray-origin offset that keeps secondary rays from hitting the
    /// surface they start on.
    let offsetScale: Float = 4e-5

    init(world: WorldKernel, settings: TracerRenderSettings) {
        self.world = world
        maxBounces = max(settings.maxBounces, 0)
        rouletteDepth = max(settings.russianRouletteDepth, 1)
        clamp = settings.indirectClamp > 0 ? settings.indirectClamp : .infinity
    }

    func radiance(origin startOrigin: Vec3, direction startDirection: Vec3,
                  rng: inout TracerRNG, rays: inout UInt64) -> Vec3 {
        let sky = world.sky
        var origin = startOrigin
        var direction = startDirection
        var result = Vec3.zero
        var throughput = Vec3(repeating: 1)
        // Camera rays and delta-like bounces see emitters at full weight.
        // After a diffuse bounce, emitters that next-event estimation can
        // sample are MIS-weighted instead of counted twice.
        var specularChain = true
        var scatterPdf: Float = 0
        var absorption = Vec3.zero
        var inAbsorbingMedium = false
        var bounce = 0
        var hit = SurfaceHit()

        path: while true {
            rays &+= 1
            let found = world.closestHit(origin: origin, direction: direction, tMax: .infinity, hit: &hit)

            if inAbsorbingMedium && found {
                let d = hit.t
                throughput *= Vec3(exp(-absorption.x * d), exp(-absorption.y * d), exp(-absorption.z * d))
            }

            guard found else {
                var environment = sky.background(direction)
                if sky.sunContains(direction) {
                    let weight = specularChain ? 1 : powerHeuristic(scatterPdf, sky.sunPdf)
                    environment += sky.sunRadiance * weight
                }
                add(throughput * environment, to: &result, indirect: bounce >= 2)
                break path
            }

            let material = world.materials[Int(hit.material)]

            if material.kind == .emissive {
                if hit.frontFace {
                    var weight: Float = 1
                    if !specularChain && hit.light >= 0 {
                        let light = world.lights[Int(hit.light)]
                        let cosine = -dot(direction, hit.normal)
                        let lightPdf = light.selectionPdf * hit.t * hit.t / max(cosine * light.area, 1e-12)
                        weight = powerHeuristic(scatterPdf, lightPdf)
                    }
                    add(throughput * material.emission * weight, to: &result, indirect: bounce >= 2)
                }
                break path
            }

            if bounce >= maxBounces { break path }

            let normal = hit.frontFace ? hit.normal : -hit.normal
            let point = hit.point
            let cosIncident = max(-dot(direction, normal), 0)
            let epsilon = offsetScale * (1 + maxMagnitude(point))

            switch material.kind {
            case .diffuse:
                let albedo = material.albedo(at: point)
                sampleLights(at: point, normal: normal, epsilon: epsilon,
                             reflectance: throughput * albedo * (1 / Float.pi),
                             indirect: bounce >= 1, result: &result, rng: &rng, rays: &rays)
                guard scatterDiffuse(normal: normal, rng: &rng, direction: &direction, pdf: &scatterPdf) else { break path }
                throughput *= albedo
                origin = point + normal * epsilon
                specularChain = false

            case .glossy:
                // A clear coat over a diffuse base. The coat reflects a Fresnel
                // fraction F of the light. Choose a lobe in proportion to each
                // one's expected contribution, then divide by that probability.
                let albedo = material.albedo(at: point)
                let fresnel = TracerOptics.schlickReflectance(cosIncident: cosIncident, n1: 1, n2: material.indexOfRefraction)
                let diffuseShare = (1 - fresnel) * luminance(albedo)
                let specularChance = min(max(fresnel / max(fresnel + diffuseShare, 1e-6), 0.1), 0.9)
                if rng.nextFloat() < specularChance {
                    guard let reflected = glossyReflection(direction, normal, roughness: material.roughness, rng: &rng) else {
                        break path
                    }
                    direction = reflected
                    throughput *= fresnel / specularChance
                    specularChain = true
                } else {
                    let base = throughput * albedo * ((1 - fresnel) / (1 - specularChance))
                    sampleLights(at: point, normal: normal, epsilon: epsilon, reflectance: base * (1 / Float.pi),
                                 indirect: bounce >= 1, result: &result, rng: &rng, rays: &rays)
                    guard scatterDiffuse(normal: normal, rng: &rng, direction: &direction, pdf: &scatterPdf) else { break path }
                    throughput = base
                    specularChain = false
                }
                origin = point + normal * epsilon

            case .metal:
                // Schlick's approximation with a colored F0: tinted head-on,
                // whitening toward grazing angles.
                let f0 = material.albedo(at: point)
                let reflectance = f0 + (Vec3(repeating: 1) - f0) * pow5(1 - cosIncident)
                guard let reflected = glossyReflection(direction, normal, roughness: material.roughness, rng: &rng) else {
                    break path
                }
                direction = reflected
                throughput *= reflectance
                origin = point + normal * epsilon
                specularChain = true

            case .glass:
                let ior = material.indexOfRefraction
                let (n1, n2): (Float, Float) = hit.frontFace ? (1, ior) : (ior, 1)
                let reflectance = TracerOptics.schlickReflectance(cosIncident: cosIncident, n1: n1, n2: n2)
                if rng.nextFloat() >= reflectance,
                   let refracted = TracerOptics.refract(direction, normal: normal, eta: n1 / n2) {
                    direction = refracted
                    origin = point - normal * epsilon
                    // Entering starts absorption inside the medium, and
                    // leaving ends it.
                    inAbsorbingMedium = hit.frontFace && material.hasAbsorption
                    absorption = inAbsorbingMedium ? material.absorption : .zero
                } else {
                    direction = reflect(direction, normal)
                    origin = point + normal * epsilon
                }
                specularChain = true

            case .emissive:
                break path
            }

            if bounce >= rouletteDepth {
                let survival = min(maxComponent(throughput), 0.95)
                if survival <= 0 || rng.nextFloat() >= survival { break path }
                throughput *= 1 / survival
            }
            bounce += 1
        }
        return result
    }

    /// Adds a contribution to the path's radiance. Indirect contributions are
    /// scaled down, keeping their hue, so no component exceeds the clamp.
    @inline(__always)
    func add(_ contribution: Vec3, to result: inout Vec3, indirect: Bool) {
        if indirect {
            let peak = maxComponent(contribution)
            if peak > clamp {
                result += contribution * (clamp / peak)
                return
            }
        }
        result += contribution
    }

    /// Draws a cosine-weighted direction about `normal`. Returns `false` for
    /// degenerate samples that graze the surface.
    @inline(__always)
    func scatterDiffuse(normal: Vec3, rng: inout TracerRNG, direction: inout Vec3, pdf: inout Float) -> Bool {
        let local = Sampling.cosineHemisphere(rng.nextFloat(), rng.nextFloat())
        guard local.z > 1e-6 else { return false }
        direction = normalize(LocalFrame(normal: normal).toWorld(local))
        pdf = local.z * (1 / Float.pi)
        return true
    }

    /// Mirror reflection jittered by `roughness`, the "fuzz" of *Ray Tracing in
    /// One Weekend*. Returns `nil` when the fuzz pushes it below the surface, so
    /// the surface absorbs the ray.
    @inline(__always)
    func glossyReflection(_ direction: Vec3, _ normal: Vec3, roughness: Float, rng: inout TracerRNG) -> Vec3? {
        var reflected = reflect(direction, normal)
        if roughness > 0 {
            let jitter = Sampling.unitSphere(rng.nextFloat(), rng.nextFloat())
            reflected = normalize(reflected + jitter * roughness)
        }
        return dot(reflected, normal) > 1e-6 ? reflected : nil
    }

    /// Next-event estimation for a diffuse lobe. It sends one shadow ray to a
    /// power-sampled quad light and one to the sun, each weighted against
    /// cosine-weighted BSDF sampling with the power heuristic.
    ///
    /// `reflectance` is the path throughput times the BRDF, `albedo / π`.
    @inline(__always)
    func sampleLights(at point: Vec3, normal: Vec3, epsilon: Float, reflectance: Vec3, indirect: Bool,
                      result: inout Vec3, rng: inout TracerRNG, rays: inout UInt64) {
        let origin = point + normal * epsilon

        if world.lightCount > 0 {
            let pick = rng.nextFloat()
            var index = 0
            while index < world.lightCount - 1 && pick >= world.lights[index].cumulative { index += 1 }
            let light = world.lights[index]
            let target = light.corner + light.edgeU * rng.nextFloat() + light.edgeV * rng.nextFloat()
            let toLight = target - origin
            let distanceSquared = dot(toLight, toLight)
            if distanceSquared > 1e-12 {
                let distance = distanceSquared.squareRoot()
                let wi = toLight * (1 / distance)
                let cosSurface = dot(wi, normal)
                let cosLight = -dot(wi, light.normal)
                if cosSurface > 0 && cosLight > 0 {
                    rays &+= 1
                    if !world.occluded(origin: origin, direction: wi, tMax: distance * (1 - 1e-4)) {
                        let lightPdf = light.selectionPdf * distanceSquared / (cosLight * light.area)
                        let bsdfPdf = cosSurface * (1 / Float.pi)
                        let weight = powerHeuristic(lightPdf, bsdfPdf)
                        add(reflectance * light.radiance * (cosSurface * weight / lightPdf), to: &result, indirect: indirect)
                    }
                }
            }
        }

        let sky = world.sky
        if sky.hasSun {
            let local = Sampling.uniformCone(rng.nextFloat(), rng.nextFloat(), cosThetaMax: sky.sunCosMax)
            let wi = normalize(sky.sunFrame.toWorld(local))
            let cosSurface = dot(wi, normal)
            if cosSurface > 0 {
                rays &+= 1
                if !world.occluded(origin: origin, direction: wi, tMax: .infinity) {
                    let bsdfPdf = cosSurface * (1 / Float.pi)
                    let weight = powerHeuristic(sky.sunPdf, bsdfPdf)
                    add(reflectance * sky.sunRadiance * (cosSurface * weight / sky.sunPdf), to: &result, indirect: indirect)
                }
            }
        }
    }
}
