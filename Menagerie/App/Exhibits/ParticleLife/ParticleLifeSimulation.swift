import Dispatch
import LifeKit
import SwiftUI

/// Numbers the simulation reports to the controls a few times a second.
struct ParticleLifeStatistics: Equatable, Sendable {
    var framesPerSecond: Double = 0
    var stepMilliseconds: Double = 0
    var meanSpeed: Double = 0
    var simulatedSeconds: Double = 0
}

/// Owns the particle world, and advances and draws it once per display frame.
///
/// This object is deliberately not observable: it changes every frame, and
/// SwiftUI must not re-evaluate views that often. ``ParticleLifeModel`` pushes
/// settings in, and the simulation reports ``ParticleLifeStatistics`` back a
/// few times a second through ``onStatistics``. Use it from the main thread
/// only; the world spreads each step over all cores internally.
final class ParticleLifeSimulation {
    /// Particles per unit of world area.
    ///
    /// Density, not particle count, decides what a rule set grows, so the
    /// world's area follows the particle count: more particles make a bigger
    /// dish with more creatures in it rather than a denser, different soup.
    static let density: Float = 2_000

    /// The longest single physics step. Longer frames are split up.
    static let maximumStep: Float = 1.0 / 60.0

    /// The seed of the first layout, so the exhibit always opens on the same,
    /// known-good arrangement.
    static let openingSeed: UInt64 = 0x5EED

    /// The reach of the pointer's force field, in points on screen.
    static let pointerRadius: CGFloat = 120

    /// Receives statistics about four times a second, from the render loop.
    var onStatistics: (@Sendable (ParticleLifeStatistics) -> Void)?

    /// Simulated seconds per real second.
    var timeScale: Double = 1

    /// When paused, the world only moves through ``stepOnce()``.
    var isPaused = false {
        didSet { lastFrameTime = nil }
    }

    private var matrix: SpeciesMatrix
    private var rules: LifeRules
    private var particleCount: Int
    private var world: ParticleWorld?
    private var isActive = false
    private var warmUp: Float = 0
    private var pendingSteps = 0
    private var lastFrameTime: TimeInterval?
    private var lastReportTime: TimeInterval = -.infinity
    private var frameMeter = FrameRateMeter()
    private var secondsPerStep: Double = 0
    private var pointer: PointerState?
    private var stageSize: CGSize = .zero

    /// The user's pointer while it is pressed on the stage.
    private struct PointerState {
        var location: CGPoint
        var repels: Bool
        var worldX: Float?
        var worldY: Float?
        var velocityX: Float = 0
        var velocityY: Float = 0
    }

    init(matrix: SpeciesMatrix, rules: LifeRules, particleCount: Int) {
        self.matrix = matrix
        self.rules = rules
        self.particleCount = particleCount
    }

    // MARK: - Lifecycle

    /// Prepares a fresh world. It is built on the first frame, once the stage
    /// size is known, and first runs `warmUp` seconds offscreen so the opening
    /// frame already shows structure.
    func start(warmUp: Float) {
        self.warmUp = warmUp
        isActive = true
        world = nil
        lastFrameTime = nil
        pointer = nil
    }

    /// Releases the world; nothing runs until ``start(warmUp:)``.
    func stop() {
        isActive = false
        world = nil
        lastFrameTime = nil
        pointer = nil
        pendingSteps = 0
    }

    // MARK: - Settings

    func setMatrix(_ matrix: SpeciesMatrix) {
        self.matrix = matrix
        world?.matrix = matrix
    }

    func setRules(_ rules: LifeRules) {
        self.rules = rules
        world?.rules = rules
    }

    /// Grows or shrinks the dish along with the particle count.
    func setParticleCount(_ count: Int) {
        particleCount = count
        guard let world else { return }
        world.resizeDomain(to: domain(aspectRatio: world.domain.aspectRatio))
        world.setParticleCount(count)
    }

    /// Throws every particle back into uniform noise.
    func scatter() {
        world?.scatter()
    }

    /// Queues one fixed step, for use while paused.
    func stepOnce() {
        pendingSteps += 1
    }

    // MARK: - Pointer

    func pointerMoved(to location: CGPoint, repels: Bool) {
        if pointer == nil {
            pointer = PointerState(location: location, repels: repels)
        } else {
            pointer?.location = location
            pointer?.repels = repels
        }
    }

    func pointerEnded() {
        pointer = nil
    }

    // MARK: - Frame

    /// Advances the world to `time` and draws it. Called by the stage's
    /// `Canvas` once per display frame.
    func renderFrame(into context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard isActive, size.width >= 2, size.height >= 2 else {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.background))
            return
        }
        stageSize = size
        let world = worldFitting(size)
        advance(world, to: time)
        draw(world, into: &context, size: size)
        report(world, at: time)
    }

    private func domain(aspectRatio: Float) -> TorusDomain {
        TorusDomain(aspectRatio: aspectRatio, area: Float(max(particleCount, 1)) / Self.density)
    }

    /// The world, created on first use and reshaped whenever the stage's
    /// proportions change.
    private func worldFitting(_ size: CGSize) -> ParticleWorld {
        let aspectRatio = Float(size.width / size.height)
        if let world {
            let current = world.domain.aspectRatio
            if abs(current - aspectRatio) > current * 0.002 {
                world.resizeDomain(to: domain(aspectRatio: aspectRatio))
            }
            return world
        }
        let fresh = ParticleWorld(
            particleCount: particleCount,
            matrix: matrix,
            rules: rules,
            domain: domain(aspectRatio: aspectRatio),
            seed: Self.openingSeed
        )
        if warmUp > 0 {
            fresh.advance(by: warmUp, maximumStep: Self.maximumStep)
        }
        world = fresh
        return fresh
    }

    private func advance(_ world: ParticleWorld, to time: TimeInterval) {
        // A long gap (a hiccup, or the first frame) must not become one huge step.
        let elapsed = lastFrameTime.map { min(max(time - $0, 0), 0.05) } ?? 0
        lastFrameTime = time
        world.pointer = pointerField(in: world, elapsed: elapsed)

        let start = DispatchTime.now().uptimeNanoseconds
        var steps = 0
        if isPaused {
            while pendingSteps > 0 {
                world.step(by: Self.maximumStep)
                pendingSteps -= 1
                steps += 1
            }
        } else {
            pendingSteps = 0
            if elapsed > 0 {
                steps = world.advance(by: Float(elapsed * timeScale), maximumStep: Self.maximumStep)
            }
        }
        guard steps > 0 else { return }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 / Double(steps)
        secondsPerStep = secondsPerStep == 0 ? seconds : secondsPerStep * 0.9 + seconds * 0.1
    }

    /// Converts the pressed pointer into a force field in world coordinates,
    /// with a smoothed velocity so a sweeping drag stirs the particles along.
    private func pointerField(in world: ParticleWorld, elapsed: TimeInterval) -> ParticlePointer? {
        guard var state = pointer, stageSize.width > 0, stageSize.height > 0 else { return nil }
        let unitsPerPointX = Double(world.domain.width) / Double(stageSize.width)
        let unitsPerPointY = Double(world.domain.height) / Double(stageSize.height)
        let x = Float(Double(state.location.x) * unitsPerPointX)
        let y = Float(Double(state.location.y) * unitsPerPointY)
        if let previousX = state.worldX, let previousY = state.worldY, elapsed > 0 {
            let limit: Float = 4
            let rawX = min(max((x - previousX) / Float(elapsed), -limit), limit)
            let rawY = min(max((y - previousY) / Float(elapsed), -limit), limit)
            state.velocityX = state.velocityX * 0.6 + rawX * 0.4
            state.velocityY = state.velocityY * 0.6 + rawY * 0.4
        }
        state.worldX = x
        state.worldY = y
        pointer = state
        return ParticlePointer(
            x: x,
            y: y,
            radius: Float(Double(Self.pointerRadius) * unitsPerPointY),
            strength: state.repels ? -16 : 11,
            velocityX: state.velocityX,
            velocityY: state.velocityY,
            stirring: 9
        )
    }

    // MARK: - Drawing

    private static let background = Color(red: 0.018, green: 0.022, blue: 0.035)

    /// Draws every particle as a bright core inside a faint halo. Each species
    /// becomes one path of cores and one of halos, so a frame costs two fills
    /// per species however many particles there are. Additive blending makes
    /// crowded regions bloom.
    private func draw(_ world: ParticleWorld, into context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(Path(bounds), with: .color(Self.background))

        let scaleX = Double(size.width) / Double(world.domain.width)
        let scaleY = Double(size.height) / Double(world.domain.height)
        // Dots are sized in world units so a structure looks the same at any
        // particle count, within limits that keep them crisp and legible.
        let core = min(max(0.0033 * scaleY, 1.2), 3.2)
        let halo = core * 3
        let speciesCount = world.speciesCount
        var cores = [Path](repeating: Path(), count: speciesCount)
        var halos = [Path](repeating: Path(), count: speciesCount)
        world.withUnsafeParticles { particles in
            for index in 0..<particles.count {
                let species = Int(particles.species[index])
                guard species < speciesCount else { continue }
                let x = Double(particles.x[index]) * scaleX
                let y = Double(particles.y[index]) * scaleY
                halos[species].addEllipse(in: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2))
                cores[species].addEllipse(in: CGRect(x: x - core, y: y - core, width: core * 2, height: core * 2))
            }
        }

        context.blendMode = .plusLighter
        for species in 0..<speciesCount {
            context.fill(halos[species], with: .color(SpeciesPalette.color(species).opacity(0.12)))
        }
        for species in 0..<speciesCount {
            context.fill(cores[species], with: .color(SpeciesPalette.color(species).opacity(0.95)))
        }

        context.blendMode = .normal
        drawPointer(into: &context)
        drawVignette(into: &context, size: size)
    }

    /// A soft disc and dashed rim showing the pointer's reach while pressed.
    private func drawPointer(into context: inout GraphicsContext) {
        guard let pointer else { return }
        let radius = Self.pointerRadius
        let center = pointer.location
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let tint = pointer.repels
            ? Color(red: 1.0, green: 0.55, blue: 0.35)
            : Color(red: 0.20, green: 0.84, blue: 0.72)
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [tint.opacity(0.16), tint.opacity(0.02)]),
            center: center,
            startRadius: 0,
            endRadius: radius
        ))
        context.stroke(disc, with: .color(tint.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
    }

    /// Darkens the corners slightly, which draws the eye to the middle.
    private func drawVignette(into context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let reach = max(size.width, size.height) * 0.75
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [.clear, Color.black.opacity(0.4)]),
            center: center,
            startRadius: reach * 0.45,
            endRadius: reach
        ))
    }

    // MARK: - Statistics

    private func report(_ world: ParticleWorld, at time: TimeInterval) {
        frameMeter.tick()
        guard abs(time - lastReportTime) >= 0.25 else { return }
        lastReportTime = time
        let statistics = ParticleLifeStatistics(
            framesPerSecond: isPaused ? 0 : frameMeter.framesPerSecond,
            stepMilliseconds: secondsPerStep * 1_000,
            meanSpeed: Double(world.meanSpeed),
            simulatedSeconds: world.elapsedTime
        )
        onStatistics?(statistics)
    }
}
