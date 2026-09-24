import XCTest
import LifeKit

final class TorusDomainTests: XCTestCase {
    private let domain = TorusDomain(width: 2, height: 1)

    func testDistanceWrapsAcrossEachSeam() {
        // Across the left/right seam.
        XCTAssertEqual(domain.distance(fromX: 0.05, y: 0.5, toX: 1.95, y: 0.5), 0.1, accuracy: 1e-6)
        // Across the top/bottom seam.
        XCTAssertEqual(domain.distance(fromX: 1, y: 0.02, toX: 1, y: 0.97), 0.05, accuracy: 1e-6)
        // Across a corner: both seams at once.
        let corner = domain.distance(fromX: 0.01, y: 0.01, toX: 1.99, y: 0.99)
        XCTAssertEqual(corner, (0.02 * 0.02 + 0.02 * 0.02).squareRoot(), accuracy: 1e-6)
        // Points that are closer directly are measured directly.
        XCTAssertEqual(domain.distance(fromX: 0.2, y: 0.2, toX: 0.5, y: 0.6), 0.5, accuracy: 1e-6)
    }

    func testDisplacementPointsTheShortWayRound() {
        let rightward = domain.displacement(fromX: 1.95, y: 0.5, toX: 0.05, y: 0.5)
        XCTAssertEqual(rightward.dx, 0.1, accuracy: 1e-6)
        XCTAssertEqual(rightward.dy, 0, accuracy: 1e-6)
        let leftward = domain.displacement(fromX: 0.05, y: 0.5, toX: 1.95, y: 0.5)
        XCTAssertEqual(leftward.dx, -0.1, accuracy: 1e-6)
        let upward = domain.displacement(fromX: 1, y: 0.97, toX: 1, y: 0.02)
        XCTAssertEqual(upward.dy, 0.05, accuracy: 1e-6)
        // Never longer than half the domain on either axis.
        let halfway = domain.displacement(fromX: 0, y: 0, toX: 1.4, y: 0.7)
        XCTAssertLessThanOrEqual(abs(halfway.dx), 1)
        XCTAssertLessThanOrEqual(abs(halfway.dy), 0.5)
    }

    func testDistanceIsSymmetric() {
        var random = LifeRandom(seed: 3)
        for _ in 0..<200 {
            let a = (random.nextFloat(from: 0, to: 2), random.nextFloat(from: 0, to: 1))
            let b = (random.nextFloat(from: 0, to: 2), random.nextFloat(from: 0, to: 1))
            XCTAssertEqual(domain.distance(fromX: a.0, y: a.1, toX: b.0, y: b.1),
                           domain.distance(fromX: b.0, y: b.1, toX: a.0, y: a.1), accuracy: 1e-6)
        }
    }

    func testWrapMapsEveryValueIntoTheDomain() {
        XCTAssertEqual(TorusDomain.wrap(0.5, period: 2), 0.5)
        XCTAssertEqual(TorusDomain.wrap(-0.1, period: 2), 1.9, accuracy: 1e-6)
        XCTAssertEqual(TorusDomain.wrap(2, period: 2), 0)
        XCTAssertEqual(TorusDomain.wrap(5.3, period: 2), 1.3, accuracy: 1e-5)
        XCTAssertEqual(TorusDomain.wrap(-4.5, period: 2), 1.5, accuracy: 1e-5)
        // A tiny negative value must not round up onto the far edge.
        let tiny = TorusDomain.wrap(-1e-9, period: 2)
        XCTAssertGreaterThanOrEqual(tiny, 0)
        XCTAssertLessThan(tiny, 2)
        // Garbage in, a valid coordinate out.
        XCTAssertEqual(TorusDomain.wrap(.nan, period: 2), 0)
        XCTAssertEqual(TorusDomain.wrap(.infinity, period: 2), 0)
        XCTAssertEqual(TorusDomain.wrap(-.infinity, period: 2), 0)
    }

    func testAspectRatioInitializerKeepsTheArea() {
        let wide = TorusDomain(aspectRatio: 1.6, area: 1.5)
        XCTAssertEqual(wide.aspectRatio, 1.6, accuracy: 1e-5)
        XCTAssertEqual(wide.area, 1.5, accuracy: 1e-5)
        let tall = TorusDomain(aspectRatio: 0.65, area: 1.5)
        XCTAssertEqual(tall.aspectRatio, 0.65, accuracy: 1e-5)
        XCTAssertEqual(tall.area, 1.5, accuracy: 1e-5)
    }
}
