import XCTest
@testable import SortKit

/// Stability, checked by tagging: each element packs a small key into its
/// high bits and its original position into the low bits, and the algorithm
/// orders elements by key alone.
final class SortStabilityTests: XCTestCase {
    private static let tagBits = 20

    private static func key(_ value: Int) -> Int {
        value >> tagBits
    }

    /// Tags `keys` with their positions.
    private static func tagged(_ keys: [Int]) -> [Int] {
        keys.enumerated().map { position, key in (key << tagBits) | position }
    }

    /// Inputs full of duplicate keys: every length up to 40 with three keys,
    /// plus larger arrays from the few-unique generator.
    private static let inputs: [[Int]] = {
        var inputs: [[Int]] = []
        var random = SortRandom(seed: 2_024)
        for n in 0...40 {
            inputs.append((0..<n).map { _ in random.next(below: 3) })
        }
        for (index, n) in [64, 100, 257].enumerated() {
            inputs.append(SortInput.fewUnique.generate(count: n, seed: UInt64(index)))
        }
        return inputs.map(tagged)
    }()

    private func traceByKey(_ algorithm: SortAlgorithm, _ input: [Int]) -> SortTrace {
        algorithm.trace(of: input, sortKey: Self.key)
    }

    /// Every algorithm must order the keys, whatever it does with ties.
    func testEveryAlgorithmOrdersKeysWhenSortingByKey() {
        for algorithm in SortAlgorithm.allCases {
            for input in Self.inputs {
                let output = referenceReplay(traceByKey(algorithm, input))
                XCTAssertEqual(output.map(Self.key), input.map(Self.key).sorted(), algorithm.name)
                XCTAssertEqual(output.sorted(), input.sorted(), "\(algorithm.name) must keep every element")
            }
        }
    }

    /// Stable algorithms keep equal keys in their original order. Because the
    /// tag is the original position, that is exactly ascending order of the
    /// packed values.
    func testStableAlgorithmsKeepEqualKeysInOrder() {
        let stable = SortAlgorithm.allCases.filter(\.isStable)
        XCTAssertEqual(Set(stable), [.bubble, .cocktailShaker, .gnome, .insertion, .merge, .radixLSD])
        for algorithm in stable {
            for input in Self.inputs {
                let trace = traceByKey(algorithm, input)
                XCTAssertEqual(referenceReplay(trace), input.sorted(), "\(algorithm.name), n=\(input.count)")

                var replayer = SortReplayer(trace: trace)
                replayer.finish()
                XCTAssertEqual(replayer.values, input.sorted())
            }
        }
    }

    /// The metadata is honest the other way too: every algorithm listed as
    /// unstable really does reorder equal keys for some input.
    func testUnstableAlgorithmsVisiblyReorderEqualKeys() {
        for algorithm in SortAlgorithm.allCases where !algorithm.isStable {
            let reordered = Self.inputs.contains { input in
                referenceReplay(traceByKey(algorithm, input)) != input.sorted()
            }
            XCTAssertTrue(reordered, "\(algorithm.name) is marked unstable but never reordered equal keys")
        }
    }
}
