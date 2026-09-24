import Foundation
import LifeKit
import Observation

/// The exhibit's state: the rules, the settings, and statistics the stage
/// reports a few times a second.
///
/// Every change is pushed straight into ``simulation``, which owns the world
/// and runs it frame by frame outside of SwiftUI's observation.
@MainActor
@Observable
final class ParticleLifeModel {
    /// The rule set the exhibit opens with.
    static let openingPreset = LifePreset.pondLife
    static let speciesRange: ClosedRange<Int> = 2...8
    static let particleRange: ClosedRange<Double> = 500...6_000
    static let radiusRange: ClosedRange<Double> = 0.04...0.16
    static let forceRange: ClosedRange<Double> = 2...24
    static let timeScaleRange: ClosedRange<Double> = 0.1...3

    private(set) var matrix: SpeciesMatrix
    private(set) var rules: LifeRules
    private(set) var particleCount: Int
    /// The preset in effect, or nil once the matrix has been edited.
    private(set) var presetName: String?
    private(set) var isSymmetric: Bool
    private(set) var isPaused = false
    private(set) var isRunning = false
    private(set) var timeScale: Double = 1
    private(set) var statistics = ParticleLifeStatistics()

    /// The frame-by-frame engine; deliberately outside observation.
    let simulation: ParticleLifeSimulation

    @ObservationIgnored private var random: LifeRandom

    init() {
        let preset = Self.openingPreset
        matrix = preset.matrix
        rules = preset.rules
        particleCount = 3_000
        presetName = preset.name
        isSymmetric = preset.matrix.isSymmetric
        // Screenshots must be reproducible; everyday use should vary.
        let seed = AppEnvironment.isCaptureTour ? 0xC0FFEE : UInt64(Date().timeIntervalSince1970 * 1_000)
        random = LifeRandom(seed: seed)
        simulation = ParticleLifeSimulation(matrix: preset.matrix, rules: preset.rules, particleCount: 3_000)
        simulation.onStatistics = { [weak self] statistics in
            guard let self else { return }
            Task { @MainActor in
                self.statistics = statistics
            }
        }
    }

    var speciesCount: Int { matrix.speciesCount }

    /// The name shown in the presets menu.
    var presetTitle: String { presetName ?? "Custom Rules" }

    /// A line describing the active preset, if any.
    var presetSummary: String? { presetName.flatMap(LifePreset.named)?.summary }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // A moment of offscreen simulation means the first frame already shows
        // structure forming; the capture tour waits until it has fully grown.
        simulation.start(warmUp: AppEnvironment.isCaptureTour ? 8 : 1.5)
    }

    func stop() {
        isRunning = false
        simulation.stop()
    }

    // MARK: - Rules

    func applyPreset(_ preset: LifePreset) {
        matrix = preset.matrix
        rules = preset.rules
        presetName = preset.name
        isSymmetric = preset.matrix.isSymmetric
        simulation.setMatrix(preset.matrix)
        simulation.setRules(preset.rules)
        simulation.scatter()
    }

    /// A fresh random matrix: symmetric when the toggle is on.
    func newRules() {
        replaceMatrix(.random(speciesCount: speciesCount, symmetric: isSymmetric, using: &random))
    }

    /// Nudges every entry a little, so the current creatures morph.
    func mutate() {
        replaceMatrix(matrix.mutated(amount: 0.15, preservingSymmetry: isSymmetric, using: &random))
    }

    func setSymmetric(_ symmetric: Bool) {
        isSymmetric = symmetric
        if symmetric && !matrix.isSymmetric {
            replaceMatrix(matrix.symmetrized())
        }
    }

    func setSpeciesCount(_ count: Int) {
        let clamped = min(max(count, Self.speciesRange.lowerBound), Self.speciesRange.upperBound)
        guard clamped != speciesCount else { return }
        replaceMatrix(matrix.resized(to: clamped, symmetric: isSymmetric, using: &random))
    }

    /// Sets how species `row` responds to species `column`, mirroring the
    /// change across the diagonal while the matrix is symmetric.
    func setAttraction(_ value: Float, row: Int, column: Int) {
        guard (0..<speciesCount).contains(row), (0..<speciesCount).contains(column) else { return }
        var updated = matrix
        updated[row, column] = value
        if isSymmetric {
            updated[column, row] = value
        }
        guard updated != matrix else { return }
        replaceMatrix(updated)
    }

    private func replaceMatrix(_ newMatrix: SpeciesMatrix) {
        matrix = newMatrix
        presetName = nil
        simulation.setMatrix(newMatrix)
    }

    // MARK: - Physics

    var interactionRadius: Double { Double(rules.interactionRadius) }

    func setInteractionRadius(_ radius: Double) {
        rules.interactionRadius = Float(radius)
        simulation.setRules(rules)
    }

    /// Friction on a 0...1 scale, where more means stickier. It maps onto a
    /// velocity half-life between 200 ms and 10 ms on a logarithmic scale,
    /// which spreads the interesting range evenly along the slider.
    var friction: Double { Self.friction(forHalfLife: Double(rules.frictionHalfLife)) }

    func setFriction(_ friction: Double) {
        rules.frictionHalfLife = Float(Self.halfLife(forFriction: friction))
        simulation.setRules(rules)
    }

    nonisolated static func halfLife(forFriction friction: Double) -> Double {
        0.2 * pow(0.05, min(max(friction, 0), 1))
    }

    nonisolated static func friction(forHalfLife halfLife: Double) -> Double {
        min(max(log(halfLife / 0.2) / log(0.05), 0), 1)
    }

    var forceStrength: Double { Double(rules.forceStrength) }

    func setForceStrength(_ strength: Double) {
        rules.forceStrength = Float(strength)
        simulation.setRules(rules)
    }

    // MARK: - Particles and time

    func setParticleCount(_ count: Double) {
        let rounded = Int((count / 100).rounded()) * 100
        let clamped = min(max(rounded, Int(Self.particleRange.lowerBound)), Int(Self.particleRange.upperBound))
        guard clamped != particleCount else { return }
        particleCount = clamped
        simulation.setParticleCount(clamped)
    }

    func scatter() {
        simulation.scatter()
    }

    func setTimeScale(_ scale: Double) {
        timeScale = scale
        simulation.timeScale = scale
    }

    func togglePause() {
        isPaused.toggle()
        simulation.isPaused = isPaused
        if isPaused {
            statistics.framesPerSecond = 0
        }
    }

    /// Advances one fixed step while paused.
    func stepOnce() {
        guard isPaused else { return }
        simulation.stepOnce()
    }

    // MARK: - Display text

    var framesPerSecondText: String {
        statistics.framesPerSecond > 0 ? "\(Int(statistics.framesPerSecond.rounded()))" : "–"
    }

    var stepTimeText: String {
        statistics.stepMilliseconds > 0 ? String(format: "%.2f ms", statistics.stepMilliseconds) : "–"
    }

    var simulatedTimeText: String {
        String(format: "%.1f s", statistics.simulatedSeconds)
    }

    var meanSpeedText: String {
        String(format: "%.3f", statistics.meanSpeed)
    }
}
