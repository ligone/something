/// A particle-life simulation: thousands of particles of a few species on a
/// torus, each pulled or pushed by its neighbors according to a
/// ``SpeciesMatrix``.
///
/// Particle state is kept as a structure of arrays of `Float`s. Particles keep
/// their index for their whole life, so any index you read stays meaningful
/// across steps. Each ``step(by:)`` sorts the particles into a uniform grid with
/// a counting sort, then computes forces in parallel chunks, and finally
/// integrates with semi-implicit Euler.
///
/// A world is not thread-safe: create, step and read it from one thread at a
/// time. Given the same seed and the same sequence of calls, a world evolves
/// identically, bit for bit, whether or not it uses several cores.
public final class ParticleWorld {
    /// The torus the particles live on.
    public private(set) var domain: TorusDomain

    /// The physical constants. Changes take effect at the next step.
    public var rules: LifeRules

    /// Who attracts whom.
    ///
    /// Assigning a matrix with a different number of species gives every
    /// particle a new species, spreading them evenly and at random.
    public var matrix: SpeciesMatrix {
        didSet {
            if matrix.speciesCount != oldValue.speciesCount {
                assignSpeciesEvenly()
            }
        }
    }

    /// An optional force field, such as the user's pointer. It acts on every
    /// step until it is set back to `nil`.
    public var pointer: ParticlePointer?

    /// Whether ``step(by:)`` may spread its work over several cores. The result
    /// is identical either way; this exists for measurement and testing.
    public var allowsConcurrency = true

    /// The number of particles.
    public private(set) var particleCount: Int

    /// The number of steps taken since the world was created.
    public internal(set) var stepCount = 0

    /// The simulated time since the world was created, in seconds.
    public internal(set) var elapsedTime: Double = 0

    /// The number of species, which is set by ``matrix``.
    public var speciesCount: Int { matrix.speciesCount }

    // Particle state, indexed by particle.
    let positionX: ParticleColumn<Float>
    let positionY: ParticleColumn<Float>
    let velocityX: ParticleColumn<Float>
    let velocityY: ParticleColumn<Float>
    let speciesColumn: ParticleColumn<UInt8>

    // Scratch rebuilt by every step, indexed by rank in cell order.
    let sortedX: ParticleColumn<Float>
    let sortedY: ParticleColumn<Float>
    let sortedSpecies: ParticleColumn<UInt8>
    let sortedCell: ParticleColumn<Int32>
    let order: ParticleColumn<Int32>
    let cellOfParticle: ParticleColumn<Int32>
    let cellStart: ParticleColumn<Int32>
    let cellCursor: ParticleColumn<Int32>
    let matrixScratch: ParticleColumn<Float>

    /// The grid the scratch arrays currently describe, or nil once particles
    /// have moved since it was built.
    var binnedGrid: CellGrid?

    /// Spare slots at the end of the cell-sorted columns, so the vectorized
    /// kernel can load a full block of eight lanes at the end of a run.
    static let lanePadding = 8

    private var random: LifeRandom

    /// Creates a world with particles scattered uniformly at random.
    ///
    /// - Parameters:
    ///   - particleCount: How many particles to create.
    ///   - matrix: The species matrix, which also sets the number of species.
    ///   - rules: The physical constants.
    ///   - domain: The torus to fill.
    ///   - seed: Determines the initial layout and every later random choice.
    public init(
        particleCount: Int,
        matrix: SpeciesMatrix,
        rules: LifeRules = LifeRules(),
        domain: TorusDomain = TorusDomain(width: 1, height: 1),
        seed: UInt64 = 0
    ) {
        precondition(particleCount >= 0, "A ParticleWorld cannot have a negative number of particles")
        self.domain = domain
        self.rules = rules
        self.matrix = matrix
        self.particleCount = particleCount
        self.random = LifeRandom(seed: seed)
        positionX = ParticleColumn(capacity: particleCount, filler: 0)
        positionY = ParticleColumn(capacity: particleCount, filler: 0)
        velocityX = ParticleColumn(capacity: particleCount, filler: 0)
        velocityY = ParticleColumn(capacity: particleCount, filler: 0)
        speciesColumn = ParticleColumn(capacity: particleCount, filler: 0)
        sortedX = ParticleColumn(capacity: particleCount + Self.lanePadding, filler: 0)
        sortedY = ParticleColumn(capacity: particleCount + Self.lanePadding, filler: 0)
        sortedSpecies = ParticleColumn(capacity: particleCount + Self.lanePadding, filler: 0)
        sortedCell = ParticleColumn(capacity: particleCount, filler: 0)
        order = ParticleColumn(capacity: particleCount, filler: 0)
        cellOfParticle = ParticleColumn(capacity: particleCount, filler: 0)
        cellStart = ParticleColumn(capacity: 64, filler: 0)
        cellCursor = ParticleColumn(capacity: 64, filler: 0)
        matrixScratch = ParticleColumn(capacity: 16 * 16, filler: 0)
        assignSpeciesEvenly()
        scatter()
    }

    // MARK: - Changing the world

    /// Moves every particle to a uniformly random position and stops it.
    public func scatter() {
        for index in 0..<particleCount {
            positionX[index] = random.nextUnit() * domain.width
            positionY[index] = random.nextUnit() * domain.height
            velocityX[index] = 0
            velocityY[index] = 0
        }
        tidyPositions(from: 0)
        binnedGrid = nil
    }

    /// Adds or removes particles.
    ///
    /// New particles appear at random positions, cycling through the species
    /// so populations stay balanced. Removal picks particles at random, so no
    /// region of the world empties out.
    public func setParticleCount(_ count: Int) {
        precondition(count >= 0, "A ParticleWorld cannot have a negative number of particles")
        if count > particleCount {
            reserve(count)
            for index in particleCount..<count {
                positionX[index] = random.nextUnit() * domain.width
                positionY[index] = random.nextUnit() * domain.height
                velocityX[index] = 0
                velocityY[index] = 0
                speciesColumn[index] = UInt8(index % speciesCount)
            }
            let previous = particleCount
            particleCount = count
            tidyPositions(from: previous)
        } else {
            while particleCount > count {
                let victim = random.nextInt(below: particleCount)
                let last = particleCount - 1
                positionX[victim] = positionX[last]
                positionY[victim] = positionY[last]
                velocityX[victim] = velocityX[last]
                velocityY[victim] = velocityY[last]
                speciesColumn[victim] = speciesColumn[last]
                particleCount = last
            }
        }
        binnedGrid = nil
    }

    /// Changes the size of the torus, stretching the particle layout to match.
    public func resizeDomain(to newDomain: TorusDomain) {
        guard newDomain != domain else { return }
        let scaleX = newDomain.width / domain.width
        let scaleY = newDomain.height / domain.height
        domain = newDomain
        for index in 0..<particleCount {
            positionX[index] *= scaleX
            positionY[index] *= scaleY
        }
        tidyPositions(from: 0)
        binnedGrid = nil
    }

    /// Places one particle exactly, which is handy for experiments and tests.
    ///
    /// The position is wrapped into the domain. Pass `species` to change the
    /// particle's species as well.
    public func setParticle(
        _ index: Int,
        x: Float,
        y: Float,
        velocityX vx: Float = 0,
        velocityY vy: Float = 0,
        species newSpecies: Int? = nil
    ) {
        precondition(index >= 0 && index < particleCount, "Particle index out of range")
        let (wrappedX, wrappedY) = domain.wrapped(x: x, y: y)
        positionX[index] = wrappedX
        positionY[index] = wrappedY
        velocityX[index] = vx.isFinite ? vx : 0
        velocityY[index] = vy.isFinite ? vy : 0
        if let newSpecies {
            precondition(newSpecies >= 0 && newSpecies < speciesCount, "Species out of range")
            speciesColumn[index] = UInt8(newSpecies)
        }
        binnedGrid = nil
    }

    // MARK: - Reading the world

    /// The position of one particle.
    public func position(of index: Int) -> (x: Float, y: Float) {
        precondition(index >= 0 && index < particleCount, "Particle index out of range")
        return (positionX[index], positionY[index])
    }

    /// The velocity of one particle, in world units per second.
    public func velocity(of index: Int) -> (x: Float, y: Float) {
        precondition(index >= 0 && index < particleCount, "Particle index out of range")
        return (velocityX[index], velocityY[index])
    }

    /// The species of one particle.
    public func species(of index: Int) -> Int {
        precondition(index >= 0 && index < particleCount, "Particle index out of range")
        return Int(speciesColumn[index])
    }

    /// How many particles belong to each species.
    public var speciesPopulations: [Int] {
        var populations = Array(repeating: 0, count: speciesCount)
        for index in 0..<particleCount {
            populations[Int(speciesColumn[index])] += 1
        }
        return populations
    }

    /// The average particle speed, in world units per second.
    public var meanSpeed: Float {
        guard particleCount > 0 else { return 0 }
        var total: Double = 0
        for index in 0..<particleCount {
            let vx = velocityX[index]
            let vy = velocityY[index]
            total += Double((vx * vx + vy * vy).squareRoot())
        }
        return Float(total / Double(particleCount))
    }

    /// Lends read-only views of the particle arrays, without copying them.
    ///
    /// This is the fast path for rendering. The buffers are valid only inside
    /// `body`; do not change the world from within it.
    public func withUnsafeParticles<Result>(_ body: (ParticleBuffers) throws -> Result) rethrows -> Result {
        let count = particleCount
        let buffers = ParticleBuffers(
            count: count,
            x: UnsafeBufferPointer(start: positionX.base, count: count),
            y: UnsafeBufferPointer(start: positionY.base, count: count),
            velocityX: UnsafeBufferPointer(start: velocityX.base, count: count),
            velocityY: UnsafeBufferPointer(start: velocityY.base, count: count),
            species: UnsafeBufferPointer(start: speciesColumn.base, count: count)
        )
        return try body(buffers)
    }

    // MARK: - Internals

    /// Ensures every column can hold `count` particles.
    private func reserve(_ count: Int) {
        for column in [positionX, positionY, velocityX, velocityY] {
            column.reserve(count, preserving: particleCount)
        }
        speciesColumn.reserve(count, preserving: particleCount)
        sortedX.reserve(count + Self.lanePadding, preserving: 0)
        sortedY.reserve(count + Self.lanePadding, preserving: 0)
        sortedSpecies.reserve(count + Self.lanePadding, preserving: 0)
        sortedCell.reserve(count, preserving: 0)
        order.reserve(count, preserving: 0)
        cellOfParticle.reserve(count, preserving: 0)
    }

    /// Gives particles evenly balanced species in a random arrangement.
    private func assignSpeciesEvenly() {
        let count = speciesCount
        for index in 0..<particleCount {
            speciesColumn[index] = UInt8(index % count)
        }
        // Fisher–Yates, so which particles share a species is random.
        var index = particleCount - 1
        while index > 0 {
            let other = random.nextInt(below: index + 1)
            let held = speciesColumn[index]
            speciesColumn[index] = speciesColumn[other]
            speciesColumn[other] = held
            index -= 1
        }
        binnedGrid = nil
    }

    /// Wraps positions from `start` onward into the domain, guarding against
    /// values that rounding pushed onto the far edge.
    private func tidyPositions(from start: Int) {
        for index in start..<max(start, particleCount) {
            positionX[index] = TorusDomain.wrap(positionX[index], period: domain.width)
            positionY[index] = TorusDomain.wrap(positionY[index], period: domain.height)
        }
    }
}

/// Read-only views of a world's particle arrays, all indexed by particle.
public struct ParticleBuffers {
    /// The number of particles.
    public let count: Int
    /// Positions, in world units.
    public let x: UnsafeBufferPointer<Float>
    public let y: UnsafeBufferPointer<Float>
    /// Velocities, in world units per second.
    public let velocityX: UnsafeBufferPointer<Float>
    public let velocityY: UnsafeBufferPointer<Float>
    /// Species indices.
    public let species: UnsafeBufferPointer<UInt8>
}
