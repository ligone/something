import Dispatch
import Foundation

extension ParticleWorld {
    /// Advances the simulation by one semi-implicit Euler step.
    ///
    /// Each particle sums the forces of its neighbors, damps its velocity by
    /// friction, adds the new acceleration, and then moves by the updated
    /// velocity. Forces for all particles are computed from the same snapshot
    /// of positions, so the order in which particles are processed never
    /// matters.
    ///
    /// - Parameter dt: The step length in seconds. Steps much longer than
    ///   1/30 s let fast particles tunnel through each other's repulsion.
    public func step(by dt: Float) {
        guard dt > 0, dt.isFinite else { return }
        let count = particleCount
        if count > 0 {
            let rules = self.rules.sanitized
            let grid = CellGrid(domain: domain, radius: rules.interactionRadius)
            bin(into: grid)
            copyMatrixToScratch()
            let pass = ForcePass(world: self, grid: grid, rules: rules, dt: dt)
            let workers = allowsConcurrency ? Self.processorCount : 1
            if workers > 1 && count >= Self.minimumParallelCount {
                // Many more chunks than cores: clustered regions cost far more
                // than empty ones, and Dispatch hands chunks to whichever
                // thread is free, which evens out the load.
                let chunks = min(workers * 8, count / 128)
                DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                    pass.run(ranks: (count * chunk / chunks)..<(count * (chunk + 1) / chunks))
                }
            } else {
                pass.run(ranks: 0..<count)
            }
            binnedGrid = nil
        }
        stepCount += 1
        elapsedTime += Double(dt)
    }

    /// Advances the simulation by `duration` seconds in equal steps no longer
    /// than `maximumStep`.
    ///
    /// - Returns: The number of steps taken.
    @discardableResult
    public func advance(by duration: Float, maximumStep: Float = 1.0 / 60.0) -> Int {
        guard duration > 0, duration.isFinite else { return 0 }
        let longest = max(maximumStep, 1e-4)
        let steps = Int(min((duration / longest).rounded(.up), 1_000))
        let dt = duration / Float(steps)
        for _ in 0..<steps {
            step(by: dt)
        }
        return steps
    }

    /// The indices of every particle within the interaction radius of the
    /// given particle, measured across the seams of the torus, in ascending
    /// order.
    ///
    /// This runs the same grid search that the force computation uses.
    public func neighbors(of index: Int) -> [Int] {
        precondition(index >= 0 && index < particleCount, "Particle index out of range")
        let radius = rules.sanitized.interactionRadius
        let radiusSquared = radius * radius
        let grid = CellGrid(domain: domain, radius: radius)
        bin(into: grid)
        let ownX = positionX[index]
        let ownY = positionY[index]
        let sortedX = self.sortedX.base
        let sortedY = self.sortedY.base
        let order = self.order.base
        var found: [Int] = []
        func consider(rank: Int, dx: Float, dy: Float) {
            let other = Int(order[rank])
            if other != index && dx * dx + dy * dy < radiusSquared {
                found.append(other)
            }
        }
        if grid.isSingleCell {
            for rank in 0..<particleCount {
                let (dx, dy) = domain.displacement(fromX: ownX, y: ownY, toX: sortedX[rank], y: sortedY[rank])
                consider(rank: rank, dx: dx, dy: dy)
            }
        } else {
            let cell = Int(cellOfParticle[index])
            grid.forEachNeighborRun(of: cell, cellStart: cellStart.base, domain: domain) { start, end, shiftX, shiftY in
                for rank in start..<end {
                    consider(rank: rank, dx: sortedX[rank] + shiftX - ownX, dy: sortedY[rank] + shiftY - ownY)
                }
            }
        }
        return found.sorted()
    }

    // MARK: - Binning

    /// Sorts the particles into grid cells with a counting sort.
    ///
    /// Afterwards `cellStart[c] ..< cellStart[c + 1]` are the ranks of the
    /// particles in cell `c`, `order` maps each rank back to its particle, and
    /// the `sorted*` columns hold a cell-ordered copy of positions and species.
    /// Walking a neighborhood then reads memory front to back. The sort is
    /// stable, so equal inputs always produce the same ranks.
    func bin(into grid: CellGrid) {
        if binnedGrid == grid { return }
        let count = particleCount
        let cells = grid.cellCount
        cellStart.reserve(cells + 1, preserving: 0)
        cellCursor.reserve(cells, preserving: 0)
        let start = cellStart.base
        let cursor = cellCursor.base
        let x = positionX.base
        let y = positionY.base
        let kinds = speciesColumn.base
        let cellOf = cellOfParticle.base

        // Count the particles in each cell, one slot to the right...
        start.update(repeating: 0, count: cells + 1)
        for index in 0..<count {
            let cell = grid.cell(x: x[index], y: y[index])
            cellOf[index] = Int32(truncatingIfNeeded: cell)
            start[cell + 1] &+= 1
        }
        // ...so that a running sum turns the counts into start offsets.
        for cell in 0..<cells {
            start[cell + 1] &+= start[cell]
        }
        // Deal every particle into the next free slot of its cell.
        cursor.update(from: start, count: cells)
        let sortedX = self.sortedX.base
        let sortedY = self.sortedY.base
        let sortedSpecies = self.sortedSpecies.base
        let sortedCell = self.sortedCell.base
        let order = self.order.base
        for index in 0..<count {
            let cell = Int(cellOf[index])
            let rank = Int(cursor[cell])
            cursor[cell] = Int32(truncatingIfNeeded: rank + 1)
            order[rank] = Int32(truncatingIfNeeded: index)
            sortedX[rank] = x[index]
            sortedY[rank] = y[index]
            sortedSpecies[rank] = kinds[index]
            sortedCell[rank] = Int32(truncatingIfNeeded: cell)
        }
        binnedGrid = grid
    }

    /// Copies the matrix into memory with a stable address for the kernel.
    private func copyMatrixToScratch() {
        let values = matrix.values
        let destination = matrixScratch.base
        values.withUnsafeBufferPointer { source in
            for index in 0..<source.count {
                destination[index] = source[index]
            }
        }
    }

    /// Below this many particles, one core finishes before others would start.
    static let minimumParallelCount = 1_024

    /// The number of cores available to the force computation.
    static let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
}

/// Everything the force computation reads or writes, captured as raw pointers
/// and constants so that worker threads never touch the world object itself.
///
/// Workers read the shared cell-ordered snapshot and write only the state of
/// particles whose ranks fall in their own chunk, so no two threads ever write
/// the same memory and none reads memory that another writes. That discipline,
/// which the compiler cannot see through raw pointers, is what makes the
/// unchecked `Sendable` conformance sound. The pointers stay valid because
/// ``ParticleWorld/step(by:)`` blocks until every chunk has finished.
private struct ForcePass: @unchecked Sendable {
    let count: Int
    let sortedX: UnsafePointer<Float>
    let sortedY: UnsafePointer<Float>
    let sortedSpecies: UnsafePointer<UInt8>
    let sortedCell: UnsafePointer<Int32>
    let order: UnsafePointer<Int32>
    let cellStart: UnsafePointer<Int32>
    let positionX: UnsafeMutablePointer<Float>
    let positionY: UnsafeMutablePointer<Float>
    let velocityX: UnsafeMutablePointer<Float>
    let velocityY: UnsafeMutablePointer<Float>
    let matrix: UnsafePointer<Float>
    let speciesCount: Int
    let grid: CellGrid
    let domain: TorusDomain
    let radiusSquared: Float
    let inverseRadius: Float
    let beta: Float
    let inverseBeta: Float
    let inverseOneMinusBeta: Float
    let forceScale: Float
    let friction: Float
    let dt: Float
    let maximumSpeed: Float
    let pointer: ParticlePointer?

    init(world: ParticleWorld, grid: CellGrid, rules: LifeRules, dt: Float) {
        count = world.particleCount
        sortedX = UnsafePointer(world.sortedX.base)
        sortedY = UnsafePointer(world.sortedY.base)
        sortedSpecies = UnsafePointer(world.sortedSpecies.base)
        sortedCell = UnsafePointer(world.sortedCell.base)
        order = UnsafePointer(world.order.base)
        cellStart = UnsafePointer(world.cellStart.base)
        positionX = world.positionX.base
        positionY = world.positionY.base
        velocityX = world.velocityX.base
        velocityY = world.velocityY.base
        matrix = UnsafePointer(world.matrixScratch.base)
        speciesCount = world.speciesCount
        self.grid = grid
        domain = world.domain
        let radius = rules.interactionRadius
        radiusSquared = radius * radius
        inverseRadius = 1 / radius
        beta = rules.repulsionRadius
        inverseBeta = 1 / rules.repulsionRadius
        inverseOneMinusBeta = 1 / (1 - rules.repulsionRadius)
        // The force grows with the radius so that a scaled-up world, with
        // every distance multiplied by k, also moves k times as fast.
        forceScale = rules.forceStrength * radius
        friction = rules.frictionFactor(overStep: dt)
        self.dt = dt
        maximumSpeed = rules.maximumSpeed
        pointer = world.pointer.flatMap { $0.isUsable ? $0 : nil }
    }

    /// Updates the particles at the given ranks of the cell order.
    func run(ranks: Range<Int>) {
        for rank in ranks {
            update(rank: rank)
        }
    }

    @inline(__always)
    private func update(rank: Int) {
        let ownX = sortedX[rank]
        let ownY = sortedY[rank]
        let attractions = matrix + Int(sortedSpecies[rank]) * speciesCount
        var sumX: Float = 0
        var sumY: Float = 0
        if grid.isSingleCell {
            accumulateAll(ownX, ownY, attractions, &sumX, &sumY)
        } else {
            let cell = Int(sortedCell[rank])
            grid.forEachNeighborRun(of: cell, cellStart: cellStart, domain: domain) { start, end, shiftX, shiftY in
                accumulate(start, end, ownX - shiftX, ownY - shiftY, attractions, &sumX, &sumY)
            }
        }

        let particle = Int(order[rank])
        var vx = velocityX[particle]
        var vy = velocityY[particle]
        var accelerationX = sumX * forceScale
        var accelerationY = sumY * forceScale
        if let pointer {
            applyPointer(pointer, ownX, ownY, vx, vy, &accelerationX, &accelerationY)
        }

        // Semi-implicit Euler: update the velocity first, then move with it.
        vx = vx * friction + accelerationX * dt
        vy = vy * friction + accelerationY * dt
        let speedSquared = vx * vx + vy * vy
        if !(speedSquared <= maximumSpeed * maximumSpeed) {
            if speedSquared.isFinite {
                let scale = maximumSpeed / speedSquared.squareRoot()
                vx *= scale
                vy *= scale
            } else {
                vx = 0
                vy = 0
            }
        }
        velocityX[particle] = vx
        velocityY[particle] = vy
        positionX[particle] = TorusDomain.wrap(ownX + vx * dt, period: domain.width)
        positionY[particle] = TorusDomain.wrap(ownY + vy * dt, period: domain.height)
    }

    /// Sums the forces from the ranks `start ..< end`, as seen from a particle
    /// at (`originX`, `originY`) that was already shifted across any seam.
    ///
    /// Candidates are processed eight at a time without branches: roughly a
    /// third of them fall inside the radius, in no predictable pattern, so a
    /// per-pair `if` would mispredict constantly. Lanes past the end of the
    /// run, beyond the radius, or at zero distance are masked out. The sorted
    /// columns carry ``ParticleWorld/lanePadding`` spare slots, so the last
    /// block may safely read past `end`.
    @inline(__always)
    private func accumulate(
        _ start: Int, _ end: Int,
        _ originX: Float, _ originY: Float,
        _ attractions: UnsafePointer<Float>,
        _ totalX: inout Float, _ totalY: inout Float
    ) {
        typealias Lanes = SIMD8<Float>
        let laneIndex = Lanes(0, 1, 2, 3, 4, 5, 6, 7)
        let ox = Lanes(repeating: originX)
        let oy = Lanes(repeating: originY)
        let reach = Lanes(repeating: radiusSquared)
        let toUnit = Lanes(repeating: inverseRadius)
        let betaLanes = Lanes(repeating: beta)
        let repulsionSlope = Lanes(repeating: inverseBeta)
        let triangleSlope = Lanes(repeating: 2 * inverseOneMinusBeta)
        var sumX = Lanes()
        var sumY = Lanes()
        var other = start
        while other < end {
            let dx = UnsafeRawPointer(sortedX + other).loadUnaligned(as: Lanes.self) - ox
            let dy = UnsafeRawPointer(sortedY + other).loadUnaligned(as: Lanes.self) - oy
            let distanceSquared = dx * dx + dy * dy
            var inside = (distanceSquared .< reach) .& (distanceSquared .> Lanes())
            if end - other < 8 {
                inside = inside .& (laneIndex .< Lanes(repeating: Float(end - other)))
            }
            if any(inside) {
                var attraction = Lanes()
                for lane in 0..<8 {
                    attraction[lane] = attractions[Int(sortedSpecies[other + lane])]
                }
                let distance = distanceSquared.squareRoot()
                let r = distance * toUnit
                // Inside beta: a linear push from -1 at contact to 0 at beta.
                let repulsion = r * repulsionSlope - 1
                // Beyond it: a triangle, min(r - beta, 1 - r), scaled to peak at 1.
                let rising = r - betaLanes
                let falling = 1 - r
                let triangle = rising.replacing(with: falling, where: falling .< rising) * triangleSlope
                var scale = repulsion.replacing(with: attraction * triangle, where: r .>= betaLanes) / distance
                scale.replace(with: 0, where: .!inside)
                sumX += dx * scale
                sumY += dy * scale
            }
            other &+= 8
        }
        totalX += sumX.sum()
        totalY += sumY.sum()
    }

    /// The single-cell fallback: every pair, by minimum image.
    private func accumulateAll(
        _ ownX: Float, _ ownY: Float,
        _ attractions: UnsafePointer<Float>,
        _ totalX: inout Float, _ totalY: inout Float
    ) {
        let halfWidth = domain.width / 2
        let halfHeight = domain.height / 2
        for other in 0..<count {
            var dx = sortedX[other] - ownX
            var dy = sortedY[other] - ownY
            if dx > halfWidth { dx -= domain.width } else if dx < -halfWidth { dx += domain.width }
            if dy > halfHeight { dy -= domain.height } else if dy < -halfHeight { dy += domain.height }
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < radiusSquared && distanceSquared > 0 {
                let distance = distanceSquared.squareRoot()
                let force = LifeRules.kernel(distance * inverseRadius, attractions[Int(sortedSpecies[other])],
                                             beta, inverseBeta, inverseOneMinusBeta)
                totalX += dx * force / distance
                totalY += dy * force / distance
            }
        }
    }

    /// Adds the pointer's pull and stirring drag.
    @inline(__always)
    private func applyPointer(
        _ pointer: ParticlePointer,
        _ ownX: Float, _ ownY: Float,
        _ vx: Float, _ vy: Float,
        _ accelerationX: inout Float, _ accelerationY: inout Float
    ) {
        let dx = TorusDomain.shortest(pointer.x - ownX, period: domain.width)
        let dy = TorusDomain.shortest(pointer.y - ownY, period: domain.height)
        let distanceSquared = dx * dx + dy * dy
        guard distanceSquared < pointer.radius * pointer.radius else { return }
        let distance = distanceSquared.squareRoot()
        let falloff = 1 - distance / pointer.radius
        if distance > 1e-6 {
            let pull = pointer.strength * falloff / distance
            accelerationX += dx * pull
            accelerationY += dy * pull
        }
        let drag = pointer.stirring * falloff
        accelerationX += (pointer.velocityX - vx) * drag
        accelerationY += (pointer.velocityY - vy) * drag
    }
}
