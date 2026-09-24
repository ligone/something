import LifeKit

// Shared fixtures and independent reference implementations for the LifeKit
// tests. The references are deliberately naive, O(n²) and scalar, so that
// they share no code with the grid search or the vectorized kernel they check.

/// A world with a random matrix, scattered at a typical density.
func makeWorld(
    particles: Int,
    species: Int = 5,
    domain: TorusDomain = TorusDomain(width: 1.7, height: 1.0),
    rules: LifeRules = LifeRules(),
    seed: UInt64 = 1
) -> ParticleWorld {
    var random = LifeRandom(seed: seed &+ 1_000)
    let matrix = SpeciesMatrix.random(speciesCount: species, using: &random)
    return ParticleWorld(particleCount: particles, matrix: matrix, rules: rules, domain: domain, seed: seed)
}

/// The neighbors of `index` found by checking every other particle.
///
/// Distances are compared with a small tolerance band, so that a pair lying
/// within rounding error of the radius is reported as neither in nor out.
func bruteForceNeighbors(of index: Int, in world: ParticleWorld, tolerance: Float = 1e-5)
    -> (definite: Set<Int>, possible: Set<Int>)
{
    let radius = world.rules.interactionRadius
    let own = world.position(of: index)
    var definite = Set<Int>()
    var possible = Set<Int>()
    for other in 0..<world.particleCount where other != index {
        let position = world.position(of: other)
        let distance = world.domain.distance(fromX: own.x, y: own.y, toX: position.x, y: position.y)
        if distance < radius - tolerance { definite.insert(other) }
        if distance < radius + tolerance { possible.insert(other) }
    }
    return (definite, possible)
}

/// The acceleration of every particle from its neighbors, summed pair by pair.
func bruteForceAccelerations(in world: ParticleWorld) -> [(x: Float, y: Float)] {
    let rules = world.rules
    let radius = rules.interactionRadius
    let domain = world.domain
    let matrix = world.matrix
    let particles = WorldSnapshot(world)
    return (0..<world.particleCount).map { index in
        let ownSpecies = Int(particles.species[index])
        var sumX: Float = 0
        var sumY: Float = 0
        for other in 0..<world.particleCount where other != index {
            let (dx, dy) = domain.displacement(fromX: particles.x[index], y: particles.y[index],
                                               toX: particles.x[other], y: particles.y[other])
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance > 0, distance < radius else { continue }
            let force = LifeRules.force(
                atDistance: distance / radius,
                attraction: matrix[ownSpecies, Int(particles.species[other])],
                repulsionRadius: rules.repulsionRadius
            )
            sumX += dx / distance * force
            sumY += dy / distance * force
        }
        let scale = rules.forceStrength * radius
        return (sumX * scale, sumY * scale)
    }
}

/// A copy of every particle's state, for exact comparisons.
struct WorldSnapshot: Equatable {
    var x: [Float] = []
    var y: [Float] = []
    var velocityX: [Float] = []
    var velocityY: [Float] = []
    var species: [UInt8] = []

    init(_ world: ParticleWorld) {
        world.withUnsafeParticles { particles in
            x = Array(particles.x)
            y = Array(particles.y)
            velocityX = Array(particles.velocityX)
            velocityY = Array(particles.velocityY)
            species = Array(particles.species)
        }
    }
}

/// Whether every particle lies inside the half-open domain rectangle.
func allParticlesInBounds(_ world: ParticleWorld) -> Bool {
    world.withUnsafeParticles { particles in
        for index in 0..<particles.count where !world.domain.contains(x: particles.x[index], y: particles.y[index]) {
            return false
        }
        return true
    }
}
