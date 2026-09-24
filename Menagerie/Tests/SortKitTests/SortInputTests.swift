import XCTest
@testable import SortKit

final class SortInputTests: XCTestCase {
    /// Reference values from an independent implementation of SplitMix64;
    /// the first matches the published test vector for seed 0.
    func testRandomMatchesSplitMix64() {
        var random = SortRandom(seed: 0)
        XCTAssertEqual(random.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(random.next(), 0x6E78_9E6A_A1B9_65F4)
        XCTAssertEqual(random.next(), 0x06C4_5D18_8009_454F)
    }

    /// Pins exact outputs, so a change to any generator can't slip by.
    func testGeneratorsMatchReferenceOutputs() {
        XCTAssertEqual(SortInput.random.generate(count: 10, seed: 42), [9, 4, 7, 6, 5, 1, 10, 3, 2, 8])
        XCTAssertEqual(SortInput.fewUnique.generate(count: 12, seed: 7), [10, 8, 12, 12, 8, 4, 2, 4, 6, 10, 2, 6])
        XCTAssertEqual(
            SortInput.nearlySorted.generate(count: 32, seed: 3),
            [1, 2, 3, 6, 5, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 20, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
        )
        XCTAssertEqual(SortInput.reversed.generate(count: 5, seed: 1), [5, 4, 3, 2, 1])
        XCTAssertEqual(SortInput.sawtooth.generate(count: 10, seed: 1), [1, 5, 9, 2, 6, 10, 3, 7, 4, 8])
    }

    func testGeneratorsAreDeterministicForASeed() {
        for shape in SortInput.allCases {
            for seed: UInt64 in [0, 1, 42, .max] {
                XCTAssertEqual(
                    shape.generate(count: 300, seed: seed),
                    shape.generate(count: 300, seed: seed),
                    "\(shape), seed \(seed)"
                )
            }
        }
    }

    func testRandomizedGeneratorsVaryWithTheSeed() {
        for shape in [SortInput.random, .nearlySorted, .fewUnique] {
            let outputs = Set((UInt64(0)..<10).map { shape.generate(count: 128, seed: $0) })
            XCTAssertEqual(outputs.count, 10, "\(shape)")
        }
    }

    func testEveryGeneratorFillsOneThroughN() {
        for shape in SortInput.allCases {
            for count in [0, 1, 2, 3, 7, 64, 1_000] {
                let values = shape.generate(count: count, seed: 9)
                XCTAssertEqual(values.count, count, "\(shape)")
                XCTAssertTrue(values.allSatisfy { (1...max(1, count)).contains($0) }, "\(shape), n=\(count)")
                if shape != .fewUnique {
                    XCTAssertEqual(values.sorted(), Array(0..<count).map { $0 + 1 }, "\(shape) must be a permutation")
                }
            }
        }
    }

    func testShapesLookTheWayTheirNamesSay() {
        let n = 256
        let maxInversions = n * (n - 1) / 2

        let reversed = SortInput.reversed.generate(count: n, seed: 0)
        XCTAssertEqual(inversionCount(reversed), maxInversions)

        let random = SortInput.random.generate(count: n, seed: 0)
        XCTAssertTrue((maxInversions / 3)...(maxInversions * 2 / 3) ~= inversionCount(random))

        let nearlySorted = SortInput.nearlySorted.generate(count: n, seed: 0)
        XCTAssertGreaterThan(inversionCount(nearlySorted), 0)
        XCTAssertLessThan(inversionCount(nearlySorted), maxInversions / 50)

        let fewUnique = SortInput.fewUnique.generate(count: n, seed: 0)
        let tally = Dictionary(grouping: fewUnique, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(tally.count, SortInput.fewUniqueLevels)
        XCTAssertTrue(tally.values.allSatisfy { abs($0 - n / SortInput.fewUniqueLevels) <= 1 })
        XCTAssertEqual(fewUnique.max(), n, "the top level reaches full height")

        let sawtooth = SortInput.sawtooth.generate(count: n, seed: 0)
        let descents = zip(sawtooth, sawtooth.dropFirst()).filter { $0 > $1 }.count
        XCTAssertEqual(descents, SortInput.sawtoothTeeth - 1)
    }

    func testBoundedRandomStaysInRange() {
        var random = SortRandom(seed: 77)
        for bound in [1, 2, 3, 10, 1_000_003] {
            for _ in 0..<1_000 {
                XCTAssertTrue((0..<bound).contains(random.next(below: bound)))
            }
        }
        var seen = Set<Int>()
        for _ in 0..<500 {
            seen.insert(random.next(below: 6))
        }
        XCTAssertEqual(seen, [0, 1, 2, 3, 4, 5])
    }
}
