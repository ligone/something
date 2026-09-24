import XCTest
@testable import SortKit

/// Operation counts must match what each algorithm is known to do.
final class SortCountTests: XCTestCase {
    func testTrivialInputsNeedNoSteps() {
        for algorithm in SortAlgorithm.allCases {
            XCTAssertEqual(algorithm.trace(of: []).stepCount, 0, algorithm.name)
            XCTAssertEqual(algorithm.trace(of: [7]).stepCount, 0, algorithm.name)
        }
    }

    /// Adaptive sorts confirm sorted input with n − 1 comparisons and no moves.
    func testAdaptiveSortsMakeOnePassOverSortedInput() {
        for algorithm in [SortAlgorithm.insertion, .bubble, .cocktailShaker, .gnome] {
            for n in 1...100 {
                let counts = algorithm.trace(of: Array(1...n)).counts
                XCTAssertEqual(counts.comparisons, n - 1, "\(algorithm.name), n=\(n)")
                XCTAssertEqual(counts.arrayWrites, 0, "\(algorithm.name), n=\(n)")
            }
        }
    }

    func testInsertionSortOnReversedInputMovesEveryPair() {
        for n in [2, 10, 64, 100] {
            let counts = SortAlgorithm.insertion.trace(of: Array((1...n).reversed())).counts
            XCTAssertEqual(counts.comparisons, n * (n - 1) / 2)
            XCTAssertEqual(counts.swaps, n * (n - 1) / 2)
        }
    }

    /// Sorts that only swap adjacent elements remove exactly one inversion
    /// per swap.
    func testAdjacentSwapSortsSwapOncePerInversion() {
        for algorithm in [SortAlgorithm.insertion, .bubble, .cocktailShaker, .gnome] {
            for shape in SortInput.allCases {
                for n in [10, 64, 150] {
                    let input = shape.generate(count: n, seed: 5)
                    let counts = algorithm.trace(of: input).counts
                    XCTAssertEqual(counts.swaps, inversionCount(input), "\(algorithm.name), \(shape), n=\(n)")
                    XCTAssertEqual(counts.writes, 0)
                }
            }
        }
    }

    func testSelectionSortComparesEveryPairOnce() {
        for shape in SortInput.allCases {
            for n in [2, 10, 64, 100] {
                let counts = SortAlgorithm.selection.trace(of: shape.generate(count: n, seed: 11)).counts
                XCTAssertEqual(counts.comparisons, n * (n - 1) / 2, "\(shape), n=\(n)")
                XCTAssertLessThanOrEqual(counts.swaps, n - 1)
            }
        }
    }

    /// Every swap settles one element for good, so a permutation with c cycles
    /// needs exactly n − c swaps.
    func testCycleSortSwapsOncePerMisplacedElementOfACycle() {
        for seed: UInt64 in 0..<20 {
            for n in [2, 9, 40, 100] {
                let input = SortInput.random.generate(count: n, seed: seed)
                let counts = SortAlgorithm.cycle.trace(of: input).counts
                XCTAssertEqual(counts.swaps, n - cycleCount(input), "n=\(n), seed=\(seed)")
            }
        }
        let fewUnique = SortInput.fewUnique.generate(count: 60, seed: 3)
        XCTAssertLessThanOrEqual(SortAlgorithm.cycle.trace(of: fewUnique).counts.swaps, 59)
    }

    /// Top-down merge sort makes at most n⌈log₂ n⌉ − 2^⌈log₂ n⌉ + 1
    /// comparisons, and one write per merged element except for right-run
    /// tails that are already in place.
    func testMergeSortStaysWithinItsComparisonBound() {
        for shape in SortInput.allCases {
            for n in [2, 3, 10, 64, 257, 1_000] {
                let counts = SortAlgorithm.merge.trace(of: shape.generate(count: n, seed: 17)).counts
                let bits = ceilLog2(n)
                XCTAssertLessThanOrEqual(counts.comparisons, n * bits - (1 << bits) + 1, "\(shape), n=\(n)")
                XCTAssertLessThanOrEqual(counts.writes, n * bits, "\(shape), n=\(n)")
                XCTAssertEqual(counts.swaps, 0)
            }
        }
    }

    func testHeapSortIsLinearithmic() {
        for shape in SortInput.allCases {
            for n in [64, 257, 1_000] {
                let counts = SortAlgorithm.heap.trace(of: shape.generate(count: n, seed: 23)).counts
                let bound = 2 * n * (ceilLog2(n) + 1)
                XCTAssertLessThanOrEqual(counts.comparisons, bound, "\(shape), n=\(n)")
            }
        }
    }

    /// Ninther and median-of-three pivots handle sorted, reversed and rotated
    /// input, and stopping on equal keys handles duplicates, so nothing goes
    /// quadratic.
    func testQuickSortAvoidsQuadraticBehaviour() {
        for n in [100, 1_000, 2_048, 5_000] {
            var inputs = SortInput.allCases.map { $0.generate(count: n, seed: 29) }
            inputs.append(Array(1...n))
            inputs.append(Array(repeating: 5, count: n))
            inputs.append([n] + Array(1..<n))
            inputs.append(Array(2...n) + [1])
            inputs.append(Array(stride(from: 1, through: n, by: 2)) + Array(stride(from: 2, through: n, by: 2)).reversed())
            for input in inputs {
                let counts = SortAlgorithm.quick.trace(of: input).counts
                XCTAssertLessThan(counts.comparisons, 3 * n * ceilLog2(n), "n=\(n), input starting \(input.prefix(8))")
            }
        }
    }

    func testRadixSortNeverComparesAndMakesOneReadAndWritePerDigit() {
        for shape in SortInput.allCases {
            for n in [2, 10, 64, 257, 1_024] {
                let input = shape.generate(count: n, seed: 31)
                let counts = SortAlgorithm.radixLSD.trace(of: input).counts
                // Base-4 digits needed to span the range of values.
                var digits = 0
                var span = input.max()! - input.min()!
                while span > 0 {
                    digits += 1
                    span >>= 2
                }
                XCTAssertEqual(counts.comparisons, 0)
                XCTAssertEqual(counts.swaps, 0)
                XCTAssertEqual(counts.reads, digits * n, "\(shape), n=\(n)")
                XCTAssertEqual(counts.writes, digits * n, "\(shape), n=\(n)")
            }
        }
    }

    /// A sorting network compares the same pairs whatever the data. For
    /// n = 2^k that is n·k(k + 1)/4 comparators.
    func testBitonicSortIsDataOblivious() {
        for n in [10, 64, 100, 257] {
            let comparisons = SortInput.allCases.map {
                SortAlgorithm.bitonic.trace(of: $0.generate(count: n, seed: 37)).counts.comparisons
            }
            XCTAssertEqual(Set(comparisons).count, 1, "n=\(n): \(comparisons)")
        }
        for k in 1...10 {
            let n = 1 << k
            let counts = SortAlgorithm.bitonic.trace(of: SortInput.random.generate(count: n, seed: 41)).counts
            XCTAssertEqual(counts.comparisons, n * k * (k + 1) / 4, "n=\(n)")
        }
    }

    func testShellSortUsesCiuraGaps() {
        XCTAssertEqual(InsertionSorts.ciuraGaps(below: 1), [])
        XCTAssertEqual(InsertionSorts.ciuraGaps(below: 2), [1])
        XCTAssertEqual(InsertionSorts.ciuraGaps(below: 257), [132, 57, 23, 10, 4, 1])
        XCTAssertEqual(InsertionSorts.ciuraGaps(below: 1_000), [701, 301, 132, 57, 23, 10, 4, 1])
        XCTAssertEqual(InsertionSorts.ciuraGaps(below: 5_000), [3548, 1577, 701, 301, 132, 57, 23, 10, 4, 1])

        let trace = SortAlgorithm.shell.trace(of: SortInput.random.generate(count: 257, seed: 43))
        let gaps = trace.operations.compactMap { operation -> Int? in
            if case .mark(.gap(let gap?)) = operation { return gap }
            return nil
        }
        XCTAssertEqual(gaps, [132, 57, 23, 10, 4, 1])
    }

    func testCombSortGapsShrinkByOnePointThree() {
        XCTAssertEqual(ExchangeSorts.nextCombGap(after: 100), 76)
        XCTAssertEqual(ExchangeSorts.nextCombGap(after: 13), 11, "10 becomes 11")
        XCTAssertEqual(ExchangeSorts.nextCombGap(after: 12), 11, "9 becomes 11")
        XCTAssertEqual(ExchangeSorts.nextCombGap(after: 11), 8)
        XCTAssertEqual(ExchangeSorts.nextCombGap(after: 2), 1)
        XCTAssertEqual(ExchangeSorts.nextCombGap(after: 1), 1)
    }

    /// Quadratic sorts really are slower than the n log n ones on random data.
    func testGrowthClassesMatchMeasuredCosts() {
        let input = SortInput.random.generate(count: 512, seed: 47)
        let steps = Dictionary(uniqueKeysWithValues: SortAlgorithm.allCases.map { ($0, $0.trace(of: input).stepCount) })
        let slowestFast = SortAlgorithm.allCases.filter { !$0.isQuadratic }.map { steps[$0]! }.max()!
        let fastestSlow = SortAlgorithm.allCases.filter(\.isQuadratic).map { steps[$0]! }.min()!
        XCTAssertLessThan(slowestFast, fastestSlow)
    }
}
