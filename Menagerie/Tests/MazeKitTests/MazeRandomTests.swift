import XCTest
@testable import MazeKit

final class MazeRandomTests: XCTestCase {
    func testMatchesPublishedSplitMix64Vectors() {
        var zero = MazeRandom(seed: 0)
        XCTAssertEqual(zero.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(zero.next(), 0x6E78_9E6A_A1B9_65F4)
        XCTAssertEqual(zero.next(), 0x06C4_5D18_8009_454F)

        // The test vectors from the SplitMix paper and Java's SplittableRandom.
        var random = MazeRandom(seed: 1_234_567)
        XCTAssertEqual(random.next(), 6_457_827_717_110_365_317)
        XCTAssertEqual(random.next(), 3_203_168_211_198_807_973)
        XCTAssertEqual(random.next(), 9_817_491_932_198_370_423)
    }

    func testUniformStaysInRangeAndIsUnbiased() {
        var random = MazeRandom(seed: 7)
        var counts = [Int](repeating: 0, count: 6)
        let draws = 60_000
        for _ in 0..<draws {
            let value = random.uniform(below: 6)
            XCTAssertTrue((0..<6).contains(value))
            counts[value] += 1
        }
        // Each face expects 10 000; allow about six standard deviations.
        for count in counts {
            XCTAssertEqual(Double(count), 10_000, accuracy: 550)
        }
        XCTAssertEqual(random.uniform(below: 1), 0)
    }

    func testUniformHandlesHugeBounds() {
        var random = MazeRandom(seed: 99)
        for _ in 0..<1_000 {
            let value = random.uniform(below: Int.max)
            XCTAssertTrue(value >= 0 && value < Int.max)
        }
    }

    func testUnitIntervalIsHalfOpen() {
        var random = MazeRandom(seed: 3)
        var sum = 0.0
        for _ in 0..<10_000 {
            let value = random.unitInterval()
            XCTAssertTrue(value >= 0 && value < 1)
            sum += value
        }
        XCTAssertEqual(sum / 10_000, 0.5, accuracy: 0.02)
    }

    func testShuffleIsADeterministicPermutation() {
        var first = MazeRandom(seed: 42)
        var second = MazeRandom(seed: 42)
        var a = Array(0..<100)
        var b = Array(0..<100)
        first.shuffle(&a)
        second.shuffle(&b)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, Array(0..<100))
        XCTAssertEqual(a.sorted(), Array(0..<100))
    }

    func testForkedStreamsAreIndependentOfConsumption() {
        let root = MazeRandom(seed: 5)
        var a = root.fork(1)
        var b = root.fork(2)
        var again = root.fork(1)
        let fromA = (0..<4).map { _ in a.next() }
        XCTAssertEqual(fromA, (0..<4).map { _ in again.next() })
        XCTAssertNotEqual(fromA, (0..<4).map { _ in b.next() })
    }
}
