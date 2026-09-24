import Foundation

/// The result of casting a camera ray through a pixel.
public struct TracerPick: Sendable, Equatable {
    /// Distance from the lens center to the hit point, along the ray.
    public var distance: Float
    /// Depth of the hit along the camera's view direction. Setting the
    /// camera's `focusDistance` to this value brings the point into focus.
    public var focusDistance: Float
    public var point: SIMD3<Float>
    public var objectIndex: Int
    public var objectName: String
}

/// A scene compiled for rendering: a BVH over all bounded primitives, plus
/// flat material, light and sky records.
///
/// A world is immutable once built, so any number of threads can trace it
/// at once. The kernel reads raw buffers that the world owns, which keeps the
/// inner loop free of reference counting and bounds checks.
public final class TracerWorld: @unchecked Sendable {
    public let scene: TracerScene
    /// The number of bounded primitives in the BVH. Infinite planes are counted
    /// separately.
    public let primitiveCount: Int
    public let bvhNodeCount: Int
    /// The number of emissive quads sampled by next-event estimation.
    public let lightCount: Int

    let kernel: WorldKernel

    private let nodeStorage: UnsafeMutablePointer<BVHNode>
    private let primitiveStorage: UnsafeMutablePointer<PrimitiveRecord>
    private let planeStorage: UnsafeMutablePointer<PlaneRecord>
    private let materialStorage: UnsafeMutablePointer<MaterialRecord>
    private let lightStorage: UnsafeMutablePointer<LightRecord>

    public init(scene: TracerScene) {
        self.scene = scene

        var materials: [MaterialRecord] = []
        var materialIndex: [TracerMaterial: Int32] = [:]
        func index(of material: TracerMaterial) -> Int32 {
            if let existing = materialIndex[material] { return existing }
            let next = Int32(materials.count)
            materials.append(MaterialRecord(material))
            materialIndex[material] = next
            return next
        }

        var bounded: [PrimitiveRecord] = []
        var items: [BVHBuilder.Item] = []
        var planes: [PlaneRecord] = []
        var lights: [LightRecord] = []

        for (objectIndex, object) in scene.objects.enumerated() {
            let material = index(of: object.material)
            let object32 = Int32(objectIndex)
            switch object.shape {
            case let .sphere(center, radius):
                guard radius != 0, radius.isFinite, isFinite(center) else { continue }
                bounded.append(PrimitiveRecord(sphereCenter: center, radius: radius, material: material, object: object32))
            case let .quad(corner, edgeU, edgeV):
                let frame = QuadFrame(corner: corner, edgeU: edgeU, edgeV: edgeV)
                guard frame.isValid else { continue }
                var light: Int32 = -1
                if object.material.kind == .emissive, maxComponent(object.material.emission) > 0 {
                    light = Int32(lights.count)
                    lights.append(LightRecord(frame: frame, radiance: object.material.emission))
                }
                bounded.append(PrimitiveRecord(quad: frame, material: material, light: light, object: object32))
            case let .plane(point, normal):
                let n = normalize(normal)
                guard lengthSquared(n) > 0 else { continue }
                planes.append(PlaneRecord(normal: n, offset: dot(n, point), material: material, object: object32))
                continue
            }
            if let bounds = object.shape.bounds {
                items.append(BVHBuilder.Item(lower: bounds.lower, upper: bounds.upper,
                                             centroid: (bounds.lower + bounds.upper) * 0.5,
                                             index: bounded.count - 1))
            }
        }

        LightRecord.assignSelectionProbabilities(&lights)
        let (nodes, order) = BVHBuilder.build(items)
        let ordered = order.map { bounded[$0] }

        primitiveCount = ordered.count
        bvhNodeCount = nodes.count
        lightCount = lights.count

        nodeStorage = TracerWorld.copy(nodes)
        primitiveStorage = TracerWorld.copy(ordered)
        planeStorage = TracerWorld.copy(planes)
        materialStorage = TracerWorld.copy(materials)
        lightStorage = TracerWorld.copy(lights)

        kernel = WorldKernel(nodes: UnsafePointer(nodeStorage), nodeCount: nodes.count,
                             primitives: UnsafePointer(primitiveStorage),
                             planes: UnsafePointer(planeStorage), planeCount: planes.count,
                             materials: UnsafePointer(materialStorage),
                             lights: UnsafePointer(lightStorage), lightCount: lights.count,
                             sky: SkyRecord(scene.sky))
    }

    deinit {
        nodeStorage.deallocate()
        primitiveStorage.deallocate()
        planeStorage.deallocate()
        materialStorage.deallocate()
        lightStorage.deallocate()
    }

    /// Copies an array of plain records into a buffer that lives as long as
    /// the world. It allocates at least one element, so the pointer is always
    /// valid.
    private static func copy<T>(_ array: [T]) -> UnsafeMutablePointer<T> {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: max(array.count, 1))
        array.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress, !buffer.isEmpty {
                pointer.initialize(from: base, count: buffer.count)
            }
        }
        return pointer
    }

    /// The nearest intersection along `ray`, with `objectIndex` set.
    public func intersect(_ ray: TracerRay, tMax: Float = .infinity) -> TracerHit? {
        var hit = SurfaceHit()
        guard kernel.closestHit(origin: ray.origin, direction: ray.direction, tMax: tMax, hit: &hit) else { return nil }
        return TracerHit(distance: hit.t, point: hit.point, normal: hit.normal, isFrontFace: hit.frontFace,
                         objectIndex: Int(hit.object))
    }

    /// Casts the lens-center ray through normalized image coordinates `(x, y)`,
    /// with `(0, 0)` at the top left, and reports what it hits. Click-to-focus
    /// uses this.
    public func pick(camera: TracerCamera, x: Float, y: Float, aspectRatio: Float) -> TracerPick? {
        let rig = CameraRig(camera: camera, aspectRatio: aspectRatio)
        let ray = rig.ray(x: x, y: y, lens: .zero)
        var hit = SurfaceHit()
        guard kernel.closestHit(origin: ray.origin, direction: ray.direction, tMax: .infinity, hit: &hit) else {
            return nil
        }
        let index = Int(hit.object)
        let name = scene.objects.indices.contains(index) ? scene.objects[index].name : ""
        return TracerPick(distance: hit.t, focusDistance: hit.t * dot(ray.direction, rig.forward),
                          point: hit.point, objectIndex: index, objectName: name)
    }

    /// Monte Carlo estimate of the radiance arriving along `ray`, averaged
    /// over `samples` independent paths. It runs single-threaded, which makes
    /// it handy for probing the integrator against analytic answers.
    public func estimateRadiance(along ray: TracerRay, samples: Int, settings: TracerRenderSettings = TracerRenderSettings(),
                                 seed: UInt64 = 1) -> TracerColor {
        let tracer = PathKernel(world: kernel, settings: settings)
        var rng = TracerRNG(seed: Hash.mix64(seed), stream: 0x5A11)
        var rays: UInt64 = 0
        var sum = Vec3.zero
        let count = max(samples, 1)
        for _ in 0..<count {
            let value = tracer.radiance(origin: ray.origin, direction: ray.direction, rng: &rng, rays: &rays)
            if isFinite(value) { sum += value }
        }
        return sum / Float(count)
    }
}
