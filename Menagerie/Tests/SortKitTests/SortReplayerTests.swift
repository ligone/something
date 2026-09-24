import XCTest
@testable import SortKit

final class SortReplayerTests: XCTestCase {
    private let input = SortInput.random.generate(count: 40, seed: 12)

    func testSteppingOneAtATimeMatchesBulkAdvance() {
        for algorithm in SortAlgorithm.allCases {
            let trace = algorithm.trace(of: input)
            var single = SortReplayer(trace: trace)
            var bulk = SortReplayer(trace: trace)
            var singleTouches: [SortTouch] = []
            var bulkTouches: [SortTouch] = []

            var steps = 0
            while single.step(onTouch: { singleTouches.append($0) }) {
                steps += 1
            }
            let taken = bulk.advance(steps: .max) { bulkTouches.append($0) }

            XCTAssertEqual(steps, trace.stepCount, "markers must not count as steps")
            XCTAssertEqual(taken, trace.stepCount)
            XCTAssertEqual(single.values, bulk.values)
            XCTAssertEqual(singleTouches, bulkTouches)
            XCTAssertEqual(single.counts, trace.counts)
            XCTAssertFalse(single.step(), "stepping a finished replay does nothing")
        }
    }

    /// Two touches per comparison and swap, one per write and read, each
    /// carrying the value at its index after the operation.
    func testTouchesDescribeEachOperation() {
        let trace = SortTrace(
            algorithm: .merge,
            input: [30, 10, 20],
            operations: [
                .mark(.range(0..<3)),
                .compare(0, 1),
                .swap(0, 1),
                .mark(.pivot(2)),
                .read(2),
                .write(index: 2, value: 99),
            ],
            output: [10, 30, 99]
        )
        var replayer = SortReplayer(trace: trace)
        XCTAssertEqual(replayer.focus.range, 0..<3, "leading markers apply before the first step")

        var touches: [SortTouch] = []
        replayer.step { touches.append($0) }
        XCTAssertEqual(touches, [
            SortTouch(kind: .compare, index: 0, value: 30),
            SortTouch(kind: .compare, index: 1, value: 10),
        ])

        touches.removeAll()
        replayer.step { touches.append($0) }
        XCTAssertEqual(touches, [
            SortTouch(kind: .swap, index: 0, value: 10),
            SortTouch(kind: .swap, index: 1, value: 30),
        ])
        XCTAssertEqual(replayer.focus.pivot, 2, "markers after a step apply straight away")

        touches.removeAll()
        replayer.advance(steps: 5) { touches.append($0) }
        XCTAssertEqual(touches, [
            SortTouch(kind: .read, index: 2, value: 20),
            SortTouch(kind: .write, index: 2, value: 99),
        ])
        XCTAssertEqual(replayer.values, [10, 30, 99])
        XCTAssertEqual(replayer.counts, SortCounts(comparisons: 1, swaps: 1, writes: 1, reads: 1))
        XCTAssertEqual(replayer.counts.arrayWrites, 3)
        XCTAssertTrue(replayer.isFinished)
        XCTAssertTrue(replayer.focus.isEmpty, "the focus clears when the replay ends")
    }

    func testSeekingMatchesAFreshReplay() {
        let trace = SortAlgorithm.quick.trace(of: input)
        var replayer = SortReplayer(trace: trace)
        for target in [trace.stepCount / 2, 10, trace.stepCount, 0, trace.stepCount / 3, trace.stepCount + 50] {
            replayer.seek(toStep: target)
            var fresh = SortReplayer(trace: trace)
            fresh.advance(steps: target)
            XCTAssertEqual(replayer.values, fresh.values, "step \(target)")
            XCTAssertEqual(replayer.counts, fresh.counts, "step \(target)")
            XCTAssertEqual(replayer.focus, fresh.focus, "step \(target)")
            XCTAssertEqual(replayer.stepsTaken, min(target, trace.stepCount))
        }
    }

    func testRewindReturnsToTheInput() {
        var replayer = SortReplayer(trace: SortAlgorithm.heap.trace(of: input))
        replayer.advance(steps: 100)
        replayer.rewind()
        XCTAssertEqual(replayer.values, input)
        XCTAssertEqual(replayer.counts, SortCounts())
        XCTAssertEqual(replayer.progress, 0)
        XCTAssertFalse(replayer.isFinished)
    }

    func testProgressRunsFromZeroToOne() {
        var replayer = SortReplayer(trace: SortAlgorithm.shell.trace(of: input))
        XCTAssertEqual(replayer.progress, 0)
        var last = 0.0
        while !replayer.isFinished {
            replayer.advance(steps: 7)
            XCTAssertGreaterThan(replayer.progress, last)
            last = replayer.progress
        }
        XCTAssertEqual(replayer.progress, 1)

        let empty = SortReplayer(trace: SortAlgorithm.shell.trace(of: []))
        XCTAssertTrue(empty.isFinished)
        XCTAssertEqual(empty.progress, 1)
    }

    /// The markers let a visualizer show what the algorithm is thinking.
    func testFocusFollowsTheAlgorithm() {
        func focuses(_ algorithm: SortAlgorithm) -> [SortFocus] {
            var replayer = SortReplayer(trace: algorithm.trace(of: input))
            var seen: [SortFocus] = []
            while replayer.step() {
                seen.append(replayer.focus)
            }
            return seen
        }

        let quick = focuses(.quick)
        XCTAssertTrue(quick.contains { $0.pivot != nil && $0.range != nil })
        XCTAssertTrue(quick.allSatisfy { focus in
            guard let pivot = focus.pivot, let range = focus.range else { return true }
            return range.contains(pivot)
        }, "the pivot lies inside the partition")

        XCTAssertTrue(focuses(.shell).contains { $0.gap == 4 })
        XCTAssertTrue(focuses(.comb).contains { $0.gap == 1 })
        XCTAssertTrue(focuses(.radixLSD).contains { $0.digit == 2 })
        XCTAssertTrue(focuses(.merge).contains { $0.range == 0..<40 }, "the final merge spans the array")
        XCTAssertTrue(focuses(.selection).contains { $0.pivot != nil })
    }
}
