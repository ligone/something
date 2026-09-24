import XCTest
@testable import SortKit

/// The sizes every algorithm is checked at: the degenerate cases, a small
/// even and odd size, a power of two and one past a power of two.
let checkedSizes = [0, 1, 2, 3, 10, 64, 257]

/// Applies a trace's operations to its input with a deliberately naive loop,
/// independent of `SortReplayer`, failing the test on any out-of-range index.
func referenceReplay(_ trace: SortTrace, file: StaticString = #filePath, line: UInt = #line) -> [Int] {
    var values = trace.input
    let valid = values.indices
    for operation in trace.operations {
        switch operation {
        case let .compare(i, j):
            XCTAssertTrue(valid.contains(i) && valid.contains(j), "compare(\(i), \(j)) out of range", file: file, line: line)
            XCTAssertNotEqual(i, j, "\(trace.algorithm) compared index \(i) with itself", file: file, line: line)
        case let .swap(i, j):
            guard valid.contains(i), valid.contains(j) else {
                XCTFail("swap(\(i), \(j)) out of range", file: file, line: line)
                continue
            }
            XCTAssertNotEqual(i, j, "\(trace.algorithm) swapped index \(i) with itself", file: file, line: line)
            values.swapAt(i, j)
        case let .write(index, value):
            guard valid.contains(index) else {
                XCTFail("write(\(index)) out of range", file: file, line: line)
                continue
            }
            values[index] = value
        case let .read(index):
            XCTAssertTrue(valid.contains(index), "read(\(index)) out of range", file: file, line: line)
        case let .mark(marker):
            switch marker {
            case .range(let range?):
                XCTAssertTrue(range.lowerBound >= 0 && range.upperBound <= values.count, "range \(range) out of bounds", file: file, line: line)
            case .pivot(let pivot?):
                XCTAssertTrue(valid.contains(pivot), "pivot \(pivot) out of range", file: file, line: line)
            case .gap(let gap?):
                XCTAssertTrue(gap >= 1 && gap < max(2, values.count), "gap \(gap) out of range", file: file, line: line)
            default:
                break
            }
        }
    }
    return values
}

/// The number of pairs i < j with values[i] > values[j].
func inversionCount(_ values: [Int]) -> Int {
    var count = 0
    for i in values.indices {
        for j in (i + 1)..<values.count where values[i] > values[j] {
            count += 1
        }
    }
    return count
}

/// The number of cycles (fixed points included) in a permutation of distinct
/// values, taken relative to its sorted order.
func cycleCount(_ values: [Int]) -> Int {
    let target = Dictionary(uniqueKeysWithValues: values.sorted().enumerated().map { ($1, $0) })
    var visited = [Bool](repeating: false, count: values.count)
    var cycles = 0
    for start in values.indices where !visited[start] {
        cycles += 1
        var i = start
        while !visited[i] {
            visited[i] = true
            i = target[values[i]]!
        }
    }
    return cycles
}

/// ⌈log₂ n⌉ for n ≥ 1.
func ceilLog2(_ n: Int) -> Int {
    var bits = 0
    while (1 << bits) < n {
        bits += 1
    }
    return bits
}

/// Every permutation of `values`, in lexicographic order of positions.
func permutations(of values: [Int]) -> [[Int]] {
    guard values.count > 1 else { return [values] }
    var result: [[Int]] = []
    for (index, first) in values.enumerated() {
        var rest = values
        rest.remove(at: index)
        for tail in permutations(of: rest) {
            result.append([first] + tail)
        }
    }
    return result
}
