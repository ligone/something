import XCTest
@testable import MazeKit

final class MazePriorityQueueTests: XCTestCase {
    func testPopsInAscendingOrder() {
        var random = MazeRandom(seed: 11)
        let values = (0..<500).map { _ in random.uniform(below: 100) }
        var queue = MazePriorityQueue<Int>()
        for value in values { queue.push(value) }
        XCTAssertEqual(queue.count, values.count)
        XCTAssertEqual(queue.peek(), values.min())

        var popped: [Int] = []
        while let value = queue.pop() { popped.append(value) }
        XCTAssertEqual(popped, values.sorted())
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.pop())
        XCTAssertNil(queue.peek())
    }

    func testHeapifyInitializer() {
        for count in [0, 1, 2, 3, 10, 257] {
            var random = MazeRandom(seed: UInt64(count))
            let values = (0..<count).map { _ in random.uniform(below: 1_000) }
            var queue = MazePriorityQueue(values)
            var popped: [Int] = []
            while let value = queue.pop() { popped.append(value) }
            XCTAssertEqual(popped, values.sorted(), "heapify of \(count) elements")
        }
    }

    func testInterleavedOperationsMatchSortedReference() {
        var random = MazeRandom(seed: 2024)
        var queue = MazePriorityQueue<Int>()
        var reference: [Int] = []
        for _ in 0..<5_000 {
            if reference.isEmpty || random.uniform(below: 3) > 0 {
                let value = random.uniform(below: 10_000)
                queue.push(value)
                reference.append(value)
                reference.sort()
            } else {
                XCTAssertEqual(queue.pop(), reference.removeFirst())
            }
            XCTAssertEqual(queue.count, reference.count)
            XCTAssertEqual(queue.peek(), reference.first)
        }
    }
}

final class DisjointSetTests: XCTestCase {
    func testUnionAndFind() {
        var sets = DisjointSet(count: 6)
        XCTAssertTrue(sets.union(0, 1))
        XCTAssertTrue(sets.union(2, 3))
        XCTAssertFalse(sets.union(1, 0), "Already joined")
        XCTAssertNotEqual(sets.find(0), sets.find(2))
        XCTAssertTrue(sets.union(1, 3))
        XCTAssertEqual(sets.find(0), sets.find(2))
        XCTAssertFalse(sets.union(0, 3))
        XCTAssertNotEqual(sets.find(4), sets.find(5))
        XCTAssertEqual(sets.find(4), 4)
    }
}
