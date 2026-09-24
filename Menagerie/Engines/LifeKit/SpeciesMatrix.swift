/// How strongly each species is attracted to every other species.
///
/// Entry `[row, column]` is the attraction that a particle of species `row`
/// feels toward a neighbor of species `column`, in `-1 ... 1`: positive values
/// pull it closer, negative values push it away. The matrix need not be
/// symmetric. When red chases green while green flees red, the pair can never
/// settle, and that imbalance is what makes particle life move.
public struct SpeciesMatrix: Hashable, Sendable {
    /// The number of species this matrix supports.
    public static let supportedSpeciesCounts: ClosedRange<Int> = 1...16

    /// The number of species; the matrix is `speciesCount × speciesCount`.
    public let speciesCount: Int

    /// The entries in row-major order.
    public private(set) var values: [Float]

    /// Creates a matrix with every entry set to `value`.
    public init(speciesCount: Int, repeating value: Float = 0) {
        precondition(Self.supportedSpeciesCounts.contains(speciesCount),
                     "SpeciesMatrix supports 1 to 16 species")
        self.speciesCount = speciesCount
        self.values = Array(repeating: Self.clamp(value), count: speciesCount * speciesCount)
    }

    /// Creates a matrix from square nested rows; entries are clamped to `-1 ... 1`.
    public init(rows: [[Float]]) {
        self.init(speciesCount: rows.count)
        for (row, entries) in rows.enumerated() {
            precondition(entries.count == rows.count, "SpeciesMatrix rows must form a square")
            for (column, value) in entries.enumerated() {
                self[row, column] = value
            }
        }
    }

    /// The attraction of species `row` toward species `column`.
    ///
    /// Assigned values are clamped to `-1 ... 1`; non-finite values become 0.
    public subscript(row: Int, column: Int) -> Float {
        get { values[index(row, column)] }
        set { values[index(row, column)] = Self.clamp(newValue) }
    }

    /// The entries as nested rows.
    public var rows: [[Float]] {
        (0..<speciesCount).map { row in
            Array(values[(row * speciesCount)..<((row + 1) * speciesCount)])
        }
    }

    /// Whether every entry equals its mirror image across the diagonal.
    public var isSymmetric: Bool {
        for row in 0..<speciesCount {
            for column in (row + 1)..<speciesCount where self[row, column] != self[column, row] {
                return false
            }
        }
        return true
    }

    /// The matrix mirrored across its diagonal.
    public var transposed: SpeciesMatrix {
        var result = self
        for row in 0..<speciesCount {
            for column in 0..<speciesCount {
                result[row, column] = self[column, row]
            }
        }
        return result
    }

    /// The nearest symmetric matrix: each entry becomes the mean of itself and
    /// its mirror image.
    public func symmetrized() -> SpeciesMatrix {
        var result = self
        for row in 0..<speciesCount {
            for column in row..<speciesCount {
                let mean = (self[row, column] + self[column, row]) / 2
                result[row, column] = mean
                result[column, row] = mean
            }
        }
        return result
    }

    /// A matrix with independent, uniformly distributed entries.
    ///
    /// With `symmetric` set, only the upper triangle is drawn and mirrored, so
    /// every pair of species feels the same pull in both directions.
    public static func random<G: RandomNumberGenerator>(
        speciesCount: Int,
        symmetric: Bool = false,
        using generator: inout G
    ) -> SpeciesMatrix {
        var result = SpeciesMatrix(speciesCount: speciesCount)
        for row in 0..<speciesCount {
            for column in 0..<speciesCount {
                if symmetric && column < row {
                    result[row, column] = result[column, row]
                } else {
                    result[row, column] = signedUnit(using: &generator)
                }
            }
        }
        return result
    }

    /// A matrix that treats the species as a ring, where each one feels only
    /// itself, the next species round the ring, and the previous one.
    ///
    /// Rings make tidy, predictable worlds: a strong `next` with a weak
    /// `previous` means every species chases its successor, so clusters spin;
    /// a small, equal pull in both directions links the species into chains.
    /// With two species the other one is both next and previous, and `next`
    /// applies.
    public static func cyclic(
        speciesCount: Int,
        own: Float,
        next: Float,
        previous: Float,
        others: Float = 0
    ) -> SpeciesMatrix {
        var result = SpeciesMatrix(speciesCount: speciesCount, repeating: others)
        for species in 0..<speciesCount {
            let following = (species + 1) % speciesCount
            let preceding = (species + speciesCount - 1) % speciesCount
            if speciesCount > 2 {
                result[species, following] = next
                result[species, preceding] = previous
            } else if speciesCount == 2 {
                result[species, following] = next
            }
            result[species, species] = own
        }
        return result
    }

    /// A copy with every entry nudged by up to `amount` in either direction.
    ///
    /// Small nudges keep the character of a rule set while shifting its
    /// balance, so the structures on screen morph rather than restart. With
    /// `preservingSymmetry`, mirrored entries receive the same nudge; a
    /// symmetric matrix therefore stays symmetric.
    public func mutated<G: RandomNumberGenerator>(
        amount: Float = 0.2,
        preservingSymmetry: Bool = false,
        using generator: inout G
    ) -> SpeciesMatrix {
        var result = self
        for row in 0..<speciesCount {
            for column in 0..<speciesCount {
                if preservingSymmetry && column < row {
                    result[row, column] = result[column, row]
                } else {
                    result[row, column] = self[row, column] + amount * signedUnit(using: &generator)
                }
            }
        }
        return result
    }

    /// A matrix for a different number of species.
    ///
    /// Entries between species that exist in both matrices are kept, and the
    /// rows and columns of new species are drawn at random.
    public func resized<G: RandomNumberGenerator>(
        to newCount: Int,
        symmetric: Bool = false,
        using generator: inout G
    ) -> SpeciesMatrix {
        var result = SpeciesMatrix.random(speciesCount: newCount, symmetric: symmetric, using: &generator)
        let shared = min(newCount, speciesCount)
        for row in 0..<shared {
            for column in 0..<shared {
                result[row, column] = self[row, column]
            }
        }
        return result
    }

    @inline(__always)
    private func index(_ row: Int, _ column: Int) -> Int {
        precondition(row >= 0 && row < speciesCount && column >= 0 && column < speciesCount,
                     "Species index out of range")
        return row * speciesCount + column
    }

    private static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, -1), 1)
    }
}

extension SpeciesMatrix: CustomStringConvertible {
    public var description: String {
        rows.map { row in
            row.map { value -> String in
                let hundredths = Int((value * 100).rounded())
                let sign = hundredths < 0 ? "-" : "+"
                let magnitude = abs(hundredths)
                let fraction = magnitude % 100 < 10 ? "0\(magnitude % 100)" : "\(magnitude % 100)"
                return "\(sign)\(magnitude / 100).\(fraction)"
            }
            .joined(separator: " ")
        }
        .joined(separator: "\n")
    }
}
