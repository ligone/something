import Foundation

/// The physical constants of a particle-life world.
///
/// Every pair of particles closer than ``interactionRadius`` interacts through
/// the force ``force(atDistance:attraction:repulsionRadius:)``: a universal
/// repulsion at short range that stops particles from overlapping, then an
/// attraction or repulsion, set by the species matrix, that rises and falls
/// like a triangle out to the edge of the radius.
public struct LifeRules: Hashable, Sendable {
    /// How far a particle can feel its neighbors (r_max), in world units.
    public var interactionRadius: Float

    /// Where universal repulsion hands over to the species force (β), as a
    /// fraction of ``interactionRadius``.
    public var repulsionRadius: Float

    /// Scales every inter-particle force.
    public var forceStrength: Float

    /// The time, in seconds, over which friction halves a particle's velocity.
    public var frictionHalfLife: Float

    /// A safety cap on particle speed, in world units per second.
    public var maximumSpeed: Float

    /// Creates a rule set. The defaults are the classic particle-life constants.
    public init(
        interactionRadius: Float = 0.1,
        repulsionRadius: Float = 0.3,
        forceStrength: Float = 10,
        frictionHalfLife: Float = 0.04,
        maximumSpeed: Float = 3
    ) {
        self.interactionRadius = interactionRadius
        self.repulsionRadius = repulsionRadius
        self.forceStrength = forceStrength
        self.frictionHalfLife = frictionHalfLife
        self.maximumSpeed = maximumSpeed
    }

    /// The dimensionless particle-life force.
    ///
    /// - Parameters:
    ///   - distance: The separation divided by the interaction radius.
    ///   - attraction: The species-matrix entry, in `-1 ... 1`.
    ///   - beta: The repulsion radius as a fraction of the interaction radius.
    /// - Returns: A positive value for a pull toward the neighbor and a
    ///   negative value for a push away from it. The function falls linearly
    ///   from -1 at contact to 0 at `beta`, then forms a triangle that peaks
    ///   at `attraction` halfway to 1 and returns to 0 at 1 and beyond.
    public static func force(atDistance distance: Float, attraction: Float, repulsionRadius beta: Float) -> Float {
        guard distance < 1 else { return 0 }
        let beta = min(max(beta, 0.01), 0.99)
        return kernel(max(distance, 0), attraction, beta, 1 / beta, 1 / (1 - beta))
    }

    /// The multiplier friction applies to velocity over a step of `dt` seconds.
    public func frictionFactor(overStep dt: Float) -> Float {
        guard frictionHalfLife > 0 else { return 0 }
        return Float(pow(0.5, Double(dt / frictionHalfLife)))
    }

    /// A copy with every constant forced into a range the integrator can handle.
    var sanitized: LifeRules {
        func finite(_ value: Float, or fallback: Float) -> Float { value.isFinite ? value : fallback }
        var rules = self
        rules.interactionRadius = max(finite(interactionRadius, or: 0.1), 1e-4)
        rules.repulsionRadius = min(max(finite(repulsionRadius, or: 0.3), 0.01), 0.99)
        rules.forceStrength = finite(forceStrength, or: 10)
        rules.frictionHalfLife = max(finite(frictionHalfLife, or: 0.04), 1e-4)
        rules.maximumSpeed = max(finite(maximumSpeed, or: 3), 1e-4)
        return rules
    }

    /// The force for `r < 1`, with the reciprocals precomputed by the caller.
    @inline(__always)
    static func kernel(_ r: Float, _ attraction: Float, _ beta: Float,
                       _ inverseBeta: Float, _ inverseOneMinusBeta: Float) -> Float {
        if r < beta {
            return r * inverseBeta - 1
        }
        return attraction * (1 - abs(2 * r - 1 - beta) * inverseOneMinusBeta)
    }
}
