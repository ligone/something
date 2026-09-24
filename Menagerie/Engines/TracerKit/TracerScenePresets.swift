import Foundation

/// The built-in scenes. Each one is framed and exposed to look good right away.
public enum TracerScenePreset: String, CaseIterable, Identifiable, Sendable {
    case cornellBox
    case marbles
    case studio

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cornellBox: return "Cornell Box"
        case .marbles: return "Marbles"
        case .studio: return "Studio"
        }
    }

    /// One line about what the scene shows off.
    public var subtitle: String {
        switch self {
        case .cornellBox: return "Color bleeding, soft shadows and a glass caustic"
        case .marbles: return "Hundreds of spheres, a BVH and a low sun"
        case .studio: return "Lacquer, gold and glass under a softbox with rim lights"
        }
    }

    public func makeScene() -> TracerScene {
        switch self {
        case .cornellBox: return SceneLibrary.cornellBox()
        case .marbles: return SceneLibrary.marbles()
        case .studio: return SceneLibrary.studio()
        }
    }
}

enum SceneLibrary {
    // MARK: Cornell Box

    /// The classic enclosure, 2 units on a side and open toward the camera,
    /// with the red wall on the left and the green on the right. A warm-white
    /// ceiling panel lights a rotated tall block, a glass sphere and a mirror
    /// ball.
    static func cornellBox() -> TracerScene {
        let white = TracerMaterial.diffuse(TracerColor(0.73, 0.71, 0.68))
        let red = TracerMaterial.diffuse(TracerColor(0.63, 0.065, 0.05))
        let green = TracerMaterial.diffuse(TracerColor(0.14, 0.45, 0.091))

        let camera = TracerCamera(position: Vec3(0, 1, 3.85), target: Vec3(0, 1, 0),
                                  verticalFieldOfView: 39, aperture: 0.04, focusDistance: 3.55)
        var scene = TracerScene(name: "Cornell Box", sky: .black, camera: camera, referenceAspectRatio: 1,
                                orbitLimits: TracerOrbitLimits(yaw: -0.5...0.5, pitch: -0.15...0.35, distance: 2.4...6),
                                exposure: 0.35, maxBounces: 10)

        scene.add("Floor", .quad(corner: Vec3(-1, 0, 1), edgeU: Vec3(2, 0, 0), edgeV: Vec3(0, 0, -2)), white)
        scene.add("Ceiling", .quad(corner: Vec3(-1, 2, -1), edgeU: Vec3(2, 0, 0), edgeV: Vec3(0, 0, 2)), white)
        scene.add("Back wall", .quad(corner: Vec3(-1, 0, -1), edgeU: Vec3(2, 0, 0), edgeV: Vec3(0, 2, 0)), white)
        scene.add("Red wall", .quad(corner: Vec3(-1, 0, 1), edgeU: Vec3(0, 0, -2), edgeV: Vec3(0, 2, 0)), red)
        scene.add("Green wall", .quad(corner: Vec3(1, 0, -1), edgeU: Vec3(0, 0, 2), edgeV: Vec3(0, 2, 0)), green)
        scene.add("Ceiling light",
                  .quad(corner: Vec3(-0.28, 1.998, -0.225), edgeU: Vec3(0.56, 0, 0), edgeV: Vec3(0, 0, 0.45)),
                  .light(TracerColor(12.5, 10.6, 8.2)))

        scene.addBox("Tall block", center: Vec3(-0.36, 0.6, -0.32), size: Vec3(0.6, 1.2, 0.6),
                     yawDegrees: 18, material: white)
        scene.add("Glass sphere", .sphere(center: Vec3(0.4, 0.34, 0.3), radius: 0.34), .glass(indexOfRefraction: 1.5))
        scene.add("Mirror ball", .sphere(center: Vec3(-0.52, 0.22, 0.42), radius: 0.22),
                  .metal(TracerColor(0.92, 0.92, 0.94), fuzz: 0))
        return scene
    }

    // MARK: Marbles

    /// A tribute to the cover of Peter Shirley's *Ray Tracing in One Weekend*:
    /// three large spheres in a field of small ones, on a checkered ground
    /// under a clear sky and a low, warm sun.
    static func marbles() -> TracerScene {
        let camera = TracerCamera(position: Vec3(13, 2, 3), target: Vec3(0, 0.4, 0),
                                  verticalFieldOfView: 20, aperture: 0.12, focusDistance: 10.2)
        let sun = TracerSun(direction: Vec3(-0.25, 0.5, 0.85), angularRadius: 2.2,
                            radiance: TracerColor(1, 0.85, 0.66) * 950)
        let sky = TracerSky(zenith: TracerColor(0.2, 0.4, 0.88), horizon: TracerColor(0.64, 0.76, 0.96),
                            ground: TracerColor(0.35, 0.33, 0.3), sun: sun)
        var scene = TracerScene(name: "Marbles", sky: sky, camera: camera, referenceAspectRatio: 1.6,
                                orbitLimits: TracerOrbitLimits(pitch: 0.02...1.3, distance: 4...30),
                                exposure: -0.35, maxBounces: 12)

        let ground = TracerTexture.checker(TracerColor(0.78, 0.76, 0.72), TracerColor(0.16, 0.17, 0.19), cellSize: 1)
        scene.add("Ground", .plane(point: .zero, normal: Vec3(0, 1, 0)), .diffuse(texture: ground))

        let heroes: [(String, Vec3, Float, TracerMaterial)] = [
            ("Glass orb", Vec3(0, 1, 0), 1, .glass(indexOfRefraction: 1.5)),
            ("Terracotta orb", Vec3(-4, 1, 0), 1, .diffuse(TracerColor(0.4, 0.2, 0.1))),
            ("Bronze orb", Vec3(4, 1, 0), 1, .metal(TracerColor(0.7, 0.6, 0.5), fuzz: 0)),
        ]
        for hero in heroes {
            scene.add(hero.0, .sphere(center: hero.1, radius: hero.2), hero.3)
        }

        var rng = TracerRNG(seed: 0x4D41_5242_4C45, stream: 7)
        func random() -> Float { rng.nextFloat() }
        func random(_ range: ClosedRange<Float>) -> Float {
            range.lowerBound + (range.upperBound - range.lowerBound) * rng.nextFloat()
        }

        for a in -11..<11 {
            for b in -11..<11 {
                let choose = random()
                let radius: Float = 0.2
                let center = Vec3(Float(a) + 0.9 * random(), radius, Float(b) + 0.9 * random())
                let clearOfHeroes = heroes.allSatisfy { hero in
                    length(center - Vec3(hero.1.x, radius, hero.1.z)) > hero.2 + radius + 0.12
                }
                guard clearOfHeroes else { continue }

                let material: TracerMaterial
                if choose < 0.6 {
                    let albedo = TracerColor(random() * random(), random() * random(), random() * random())
                    material = .diffuse(albedo)
                } else if choose < 0.78 {
                    let hue = TracerColor(random(0.1...0.95), random(0.1...0.95), random(0.1...0.95))
                    material = .glossy(hue, roughness: random(0...0.08))
                } else if choose < 0.92 {
                    let tint = TracerColor(random(0.5...1), random(0.5...1), random(0.5...1))
                    material = .metal(tint, fuzz: random(0...0.35))
                } else {
                    let tint = TracerColor(random(0.3...1), random(0.3...1), random(0.3...1))
                    material = .glass(indexOfRefraction: 1.5, transmittance: tint)
                }
                scene.add("Marble", .sphere(center: center, radius: radius), material)
            }
        }
        return scene
    }

    // MARK: Studio

    /// A product shot: lacquered, metallic and glass spheres on a dark gloss
    /// floor, under a large softbox with warm and cool rim lights, a dim fill
    /// card and an overhead scrim.
    static func studio() -> TracerScene {
        let camera = TracerCamera(position: Vec3(0.4, 1.7, 7.4), target: Vec3(0, 0.75, 0.2),
                                  verticalFieldOfView: 30, aperture: 0.14, focusDistance: 7.1)
        // A dim glow at the horizon. The glossy floor reflects more of it
        // toward grazing angles, so floor and backdrop blend like a
        // seamless paper sweep.
        let sky = TracerSky(zenith: TracerColor(0.006, 0.006, 0.008), horizon: TracerColor(0.1, 0.098, 0.105),
                            ground: TracerColor(0.1, 0.098, 0.105))
        var scene = TracerScene(name: "Studio", sky: sky, camera: camera, referenceAspectRatio: 1.45,
                                orbitLimits: TracerOrbitLimits(pitch: 0.02...1.2, distance: 3.5...16),
                                exposure: 0.45, maxBounces: 10)

        scene.add("Floor", .plane(point: .zero, normal: Vec3(0, 1, 0)),
                  .glossy(TracerColor(0.045, 0.045, 0.05), roughness: 0.03))

        scene.add("Ruby lacquer", .sphere(center: Vec3(0, 1, 0), radius: 1),
                  .glossy(TracerColor(0.72, 0.035, 0.04), roughness: 0))
        scene.add("Gold", .sphere(center: Vec3(-2.05, 0.72, 0.55), radius: 0.72),
                  .metal(TracerColor(1.0, 0.77, 0.34), fuzz: 0.06))
        scene.add("Crystal", .sphere(center: Vec3(1.85, 0.62, 0.85), radius: 0.62),
                  .glass(indexOfRefraction: 1.52, transmittance: TracerColor(0.93, 0.97, 1)))
        scene.add("Porcelain", .sphere(center: Vec3(-0.75, 0.38, 1.75), radius: 0.38),
                  .glossy(TracerColor(0.85, 0.84, 0.8), roughness: 0))
        scene.add("Cobalt", .sphere(center: Vec3(0.85, 0.3, 2.05), radius: 0.3),
                  .glossy(TracerColor(0.04, 0.12, 0.6), roughness: 0.02))
        scene.add("Chrome", .sphere(center: Vec3(2.75, 0.34, -1.1), radius: 0.34),
                  .metal(TracerColor(0.95, 0.95, 0.97), fuzz: 0))

        let subject = Vec3(0, 0.9, 0.3)
        scene.add("Softbox", facingQuad(center: Vec3(-1.6, 4.8, 3.4), toward: subject, width: 3.6, height: 2.4),
                  .light(TracerColor(9.5, 9.1, 8.5)))
        scene.add("Warm rim", facingQuad(center: Vec3(-6.2, 2.4, -3.6), toward: subject, width: 0.8, height: 3.4),
                  .light(TracerColor(14, 7.2, 2.4)))
        scene.add("Cool rim", facingQuad(center: Vec3(6.2, 2.6, -3.4), toward: subject, width: 0.8, height: 3.4),
                  .light(TracerColor(2.4, 5.4, 14)))
        // A large, dim card at front right, and a scrim overhead. They lift the
        // shadow sides and give the metals and glass something to mirror.
        scene.add("Fill card", facingQuad(center: Vec3(5.2, 2.2, 5.4), toward: subject, width: 4.2, height: 3.2),
                  .light(TracerColor(0.9, 0.92, 1.0)))
        scene.add("Scrim", .quad(corner: Vec3(-6, 7.5, -5), edgeU: Vec3(12, 0, 0), edgeV: Vec3(0, 0, 10)),
                  .light(TracerColor(0.42, 0.42, 0.45)))
        return scene
    }

    /// A rectangle centered at `center` whose lit front face points at
    /// `target`.
    static func facingQuad(center: Vec3, toward target: Vec3, width: Float, height: Float) -> TracerShape {
        let forward = normalize(target - center)
        var right = cross(forward, Vec3(0, 1, 0))
        if lengthSquared(right) < 1e-8 { right = Vec3(1, 0, 0) }
        right = normalize(right)
        let up = cross(right, forward)
        // cross(up, right) == forward, so the emitting side faces the target.
        let edgeU = up * height
        let edgeV = right * width
        return .quad(corner: center - (edgeU + edgeV) * 0.5, edgeU: edgeU, edgeV: edgeV)
    }
}
