import XCTest
import LifeKit

final class SpeciesMatrixTests: XCTestCase {
    func testSymmetricGenerationIsSymmetric() {
        for speciesCount in 1...8 {
            for seed in 0..<10 {
                var random = LifeRandom(seed: UInt64(seed))
                let matrix = SpeciesMatrix.random(speciesCount: speciesCount, symmetric: true, using: &random)
                XCTAssertTrue(matrix.isSymmetric, "\(speciesCount) species, seed \(seed)")
                for row in 0..<speciesCount {
                    for column in 0..<speciesCount {
                        XCTAssertEqual(matrix[row, column], matrix[column, row])
                    }
                }
            }
        }
    }

    func testAsymmetricGenerationIsNotForcedSymmetric() {
        var random = LifeRandom(seed: 11)
        let matrices = (0..<10).map { _ in SpeciesMatrix.random(speciesCount: 4, using: &random) }
        XCTAssertTrue(matrices.contains { !$0.isSymmetric })
    }

    func testRandomEntriesCoverTheFullRange() {
        var random = LifeRandom(seed: 5)
        let values = (0..<50).flatMap { _ in SpeciesMatrix.random(speciesCount: 8, using: &random).values }
        XCTAssertTrue(values.allSatisfy { $0 >= -1 && $0 <= 1 })
        XCTAssertLessThan(values.min() ?? 0, -0.95)
        XCTAssertGreaterThan(values.max() ?? 0, 0.95)
        let mean = values.reduce(0, +) / Float(values.count)
        XCTAssertEqual(mean, 0, accuracy: 0.05)
    }

    func testSymmetrizedAveragesMirroredEntries() {
        var random = LifeRandom(seed: 9)
        let matrix = SpeciesMatrix.random(speciesCount: 6, using: &random)
        let symmetric = matrix.symmetrized()
        XCTAssertTrue(symmetric.isSymmetric)
        for row in 0..<6 {
            for column in 0..<6 {
                XCTAssertEqual(symmetric[row, column], (matrix[row, column] + matrix[column, row]) / 2, accuracy: 1e-6)
            }
        }
        XCTAssertEqual(matrix.transposed.transposed, matrix)
    }

    func testMutationNudgesWithoutBreakingSymmetryOrBounds() {
        var random = LifeRandom(seed: 21)
        let symmetric = SpeciesMatrix.random(speciesCount: 5, symmetric: true, using: &random)
        let mutated = symmetric.mutated(amount: 0.2, preservingSymmetry: true, using: &random)
        XCTAssertTrue(mutated.isSymmetric)
        XCTAssertNotEqual(mutated, symmetric)
        for (before, after) in zip(symmetric.values, mutated.values) {
            XCTAssertLessThanOrEqual(abs(after - before), 0.2 + 1e-6)
            XCTAssertTrue(after >= -1 && after <= 1)
        }
        let saturated = SpeciesMatrix(speciesCount: 3, repeating: 1)
        let pushed = saturated.mutated(amount: 0.5, using: &random)
        XCTAssertTrue(pushed.values.allSatisfy { $0 <= 1 })
    }

    func testEntriesAreClampedAndSanitized() {
        var matrix = SpeciesMatrix(speciesCount: 2)
        matrix[0, 1] = 3
        matrix[1, 0] = -7
        matrix[1, 1] = .nan
        XCTAssertEqual(matrix[0, 1], 1)
        XCTAssertEqual(matrix[1, 0], -1)
        XCTAssertEqual(matrix[1, 1], 0)
        XCTAssertEqual(SpeciesMatrix(rows: [[2, -2], [0.5, .infinity]]).rows, [[1, -1], [0.5, 0]])
    }

    func testResizingKeepsTheSharedBlock() {
        var random = LifeRandom(seed: 2)
        let matrix = SpeciesMatrix.random(speciesCount: 4, using: &random)
        let larger = matrix.resized(to: 6, using: &random)
        let smaller = matrix.resized(to: 2, using: &random)
        XCTAssertEqual(larger.speciesCount, 6)
        XCTAssertEqual(smaller.speciesCount, 2)
        for row in 0..<2 {
            for column in 0..<2 {
                XCTAssertEqual(larger[row, column], matrix[row, column])
                XCTAssertEqual(smaller[row, column], matrix[row, column])
            }
        }
        XCTAssertEqual(larger[3, 3], matrix[3, 3])
    }

    func testCyclicMatrixLinksEachSpeciesToItsNeighbors() {
        let ring = SpeciesMatrix.cyclic(speciesCount: 4, own: 1, next: 0.5, previous: -0.25, others: -1)
        XCTAssertEqual(ring.rows, [
            [1, 0.5, -1, -0.25],
            [-0.25, 1, 0.5, -1],
            [-1, -0.25, 1, 0.5],
            [0.5, -1, -0.25, 1],
        ])
        let pair = SpeciesMatrix.cyclic(speciesCount: 2, own: 0.3, next: 0.6, previous: -0.6)
        XCTAssertEqual(pair.rows, [[0.3, 0.6], [0.6, 0.3]])
    }
}
