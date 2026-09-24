import XCTest
@testable import SortKit

/// Replaying any algorithm's trace on its input must produce exactly the
/// sorted input.
final class SortCorrectnessTests: XCTestCase {
    /// Every algorithm × every input shape × every checked size.
    func testEveryAlgorithmSortsEveryInputShapeAndSize() {
        for algorithm in SortAlgorithm.allCases {
            for shape in SortInput.allCases {
                for size in checkedSizes {
                    let input = shape.generate(count: size, seed: UInt64(size) &* 7919 &+ 1)
                    assertSorts(algorithm, input, "\(shape) n=\(size)")
                }
            }
        }
    }

    /// Every length from 0 to 70 catches off-by-one errors that the checked
    /// sizes might miss, especially in bitonic sort's odd-length merges.
    func testEveryLengthUpToSeventy() {
        for algorithm in SortAlgorithm.allCases {
            for size in 0...70 {
                let input = SortInput.random.generate(count: size, seed: UInt64(1_000 + size))
                assertSorts(algorithm, input, "n=\(size)")
            }
        }
    }

    /// Exhaustive: all 720 orderings of six distinct values, and all orderings
    /// of a six-element multiset with repeats.
    func testEveryPermutationOfSmallArrays() {
        let distinct = permutations(of: [1, 2, 3, 4, 5, 6])
        let repeated = Set(permutations(of: [1, 1, 2, 2, 2, 3])).sorted { $0.lexicographicallyPrecedes($1) }
        XCTAssertEqual(distinct.count, 720)
        XCTAssertEqual(repeated.count, 60)
        for algorithm in SortAlgorithm.allCases {
            for input in distinct + repeated {
                assertSorts(algorithm, input, "\(input)")
            }
        }
    }

    /// Negative numbers, duplicates and the extremes of `Int`, which stress
    /// radix sort's key offsetting in particular.
    func testNegativeAndExtremeValues() {
        let inputs: [[Int]] = [
            [5, -3, 0, -3, 12, -100, 7, 0],
            [Int.max, Int.min, 0, -1, 1, Int.max, Int.min],
            [-1, -2, -3, -4, -5, -6, -7, -8, -9],
            Array(repeating: 42, count: 17),
            (0..<50).map { ($0 * 7_919) % 23 - 11 },
        ]
        for algorithm in SortAlgorithm.allCases {
            for input in inputs {
                assertSorts(algorithm, input, "\(input)")
            }
        }
    }

    func testLargeInputsSortWithFastAlgorithms() {
        let fast: [SortAlgorithm] = [.shell, .comb, .heap, .merge, .quick, .radixLSD, .bitonic]
        for algorithm in fast {
            for shape in SortInput.allCases {
                let input = shape.generate(count: 1_024, seed: 99)
                assertSorts(algorithm, input, "\(shape) n=1024")
            }
        }
    }

    /// Checks the trace three ways: its recorded output, an independent naive
    /// replay, and a `SortReplayer`.
    private func assertSorts(
        _ algorithm: SortAlgorithm,
        _ input: [Int],
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = input.sorted()
        let trace = algorithm.trace(of: input)
        XCTAssertEqual(trace.algorithm, algorithm, file: file, line: line)
        XCTAssertEqual(trace.input, input, file: file, line: line)
        XCTAssertEqual(trace.output, expected, "\(algorithm.name) output, \(context)", file: file, line: line)
        XCTAssertEqual(referenceReplay(trace, file: file, line: line), expected, "\(algorithm.name) replay, \(context)", file: file, line: line)

        var replayer = SortReplayer(trace: trace)
        replayer.finish()
        XCTAssertTrue(replayer.isFinished, file: file, line: line)
        XCTAssertEqual(replayer.values, expected, "\(algorithm.name) replayer, \(context)", file: file, line: line)
        XCTAssertEqual(replayer.counts, trace.counts, file: file, line: line)
    }
}
