import XCTest
@testable import CalculusKit

final class NumericsTests: XCTestCase {
    private func analysis(_ source: String) throws -> FunctionAnalysis {
        try FunctionAnalysis(parsing: source)
    }

    // MARK: Roots

    func testBrent() {
        let root = RootFinder.brent({ cos($0) - $0 }, lower: 0, upper: 1)
        XCTAssertEqual(root ?? .nan, 0.7390851332151607, accuracy: 1e-15)
        XCTAssertNil(RootFinder.brent({ $0 * $0 + 1 }, lower: -1, upper: 2), "No sign change, no root")
        XCTAssertEqual(RootFinder.brent({ $0 }, lower: 0, upper: 1), 0)
    }

    func testRootsOfQuadratic() throws {
        let roots = try analysis("x^2 - 2").features(in: -5...5).roots
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(roots[0], -2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(roots[1], 2.0.squareRoot(), accuracy: 1e-12)
    }

    func testRootsOfSine() throws {
        let roots = try analysis("sin(x)").features(in: -10...10).roots
        XCTAssertEqual(roots.count, 7)
        for (root, k) in zip(roots, -3...3) {
            XCTAssertEqual(root, Double(k) * .pi, accuracy: 1e-12)
        }
    }

    func testTangentRootsAreFound() throws {
        // x² and (x − 1)² touch zero without crossing it.
        XCTAssertEqual(try analysis("x^2").features(in: -3.3...4.1).roots.map { abs($0) < 1e-9 }, [true])
        let shifted = try analysis("(x - 1)^2").features(in: -3.3...4.1).roots
        XCTAssertEqual(shifted.count, 1)
        XCTAssertEqual(shifted.first ?? .nan, 1, accuracy: 1e-9)
        let cosine = try analysis("cos(x) + 1").features(in: -7...7).roots
        XCTAssertEqual(cosine.count, 2)
        XCTAssertEqual(cosine.last ?? .nan, .pi, accuracy: 1e-9)
    }

    func testPolesAreNotRoots() throws {
        let tangent = try analysis("tan(x)").features(in: -4...4).roots
        XCTAssertEqual(tangent.count, 3, "tan changes sign at ±π/2 but those are poles")
        XCTAssertEqual(try analysis("1/x").features(in: -3...3).roots, [])
        XCTAssertEqual(try analysis("sgn(x - 0.5) + 2").features(in: -3...3).roots, [])
    }

    func testRootsAtTheEdgeOfTheDomain() throws {
        let circle = try analysis("sqrt(1 - x^2)").features(in: -2...2).roots
        XCTAssertEqual(circle.count, 2)
        XCTAssertEqual(circle[0], -1, accuracy: 1e-9)
        XCTAssertEqual(circle[1], 1, accuracy: 1e-9)
    }

    // MARK: Extrema and inflection points

    func testExtremaOfCubic() throws {
        let features = try analysis("x^3 - 3x").features(in: -3...3)
        XCTAssertEqual(features.extrema.count, 2)
        let maximum = features.extrema[0]
        let minimum = features.extrema[1]
        XCTAssertEqual(maximum.kind, .maximum)
        XCTAssertEqual(maximum.x, -1, accuracy: 1e-10)
        XCTAssertEqual(maximum.y, 2, accuracy: 1e-10)
        XCTAssertEqual(minimum.kind, .minimum)
        XCTAssertEqual(minimum.x, 1, accuracy: 1e-10)
        XCTAssertEqual(minimum.y, -2, accuracy: 1e-10)

        XCTAssertEqual(features.inflectionPoints.count, 1)
        XCTAssertEqual(features.inflectionPoints[0].x, 0, accuracy: 1e-10)
    }

    func testStationaryPointsThatAreNotExtrema() throws {
        let features = try analysis("x^3").features(in: -2...2)
        XCTAssertEqual(features.extrema, [], "x³ is flat at 0 but keeps rising")
        XCTAssertEqual(features.inflectionPoints.count, 1)
    }

    func testCornersAndCusps() throws {
        let absolute = try analysis("|x - 0.3|").features(in: -2...2).extrema
        XCTAssertEqual(absolute.count, 1)
        XCTAssertEqual(absolute.first?.kind, .minimum)
        XCTAssertEqual(absolute.first?.x ?? .nan, 0.3, accuracy: 1e-9)

        let cusp = try analysis("x^(2/3)").features(in: -2...2).extrema
        XCTAssertEqual(cusp.count, 1)
        XCTAssertEqual(cusp.first?.x ?? .nan, 0, accuracy: 1e-9)
    }

    func testPolesAreNotExtremaOrInflections() throws {
        let features = try analysis("1/x^2").features(in: -2...2)
        XCTAssertEqual(features.extrema, [])
        XCTAssertEqual(try analysis("1/x").features(in: -2...2).inflectionPoints, [])
        let tangent = try analysis("tan(x)").features(in: -4...4).inflectionPoints
        XCTAssertEqual(tangent.map { ($0.x / .pi).rounded() }, [-1, 0, 1])
    }

    func testRemovableSingularity() throws {
        let features = try analysis("sin(x)/x").features(in: -5...5)
        XCTAssertTrue(features.extrema.contains { abs($0.x) < 1e-9 && $0.kind == .maximum && abs($0.y - 1) < 1e-9 })
        XCTAssertFalse(features.roots.contains { abs($0) < 1 })
    }

    func testGaussianInflectionPoints() throws {
        let features = try analysis("e^(-x^2)").features(in: -3...3)
        assertClose(features.inflectionPoints.map(\.x), [-0.5.squareRoot(), 0.5.squareRoot()], accuracy: 1e-9)
    }

    // MARK: Integrals

    func testIntegrals() throws {
        let sine = try analysis("sin(x)").integral(from: 0, to: .pi)
        XCTAssertEqual(sine.value, 2, accuracy: 1e-10)
        XCTAssertEqual(sine.status, .converged)

        XCTAssertEqual(try analysis("x^2").integral(from: 0, to: 1).value, 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(try analysis("e^(-x^2)").integral(from: -10, to: 10).value, Double.pi.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(try analysis("1/(1+x^2)").integral(from: -1, to: 1).value, .pi / 2, accuracy: 1e-10)
        XCTAssertEqual(try analysis("x^x").integral(from: 0, to: 1).value, 0.7834305107121344, accuracy: 1e-9)
    }

    func testReversedBoundsNegate() throws {
        let f = try analysis("x^3 + 1")
        XCTAssertEqual(f.integral(from: 2, to: -1).value, -f.integral(from: -1, to: 2).value, accuracy: 1e-12)
        XCTAssertEqual(f.integral(from: 1, to: 1).value, 0)
    }

    func testIntegrableSingularities() throws {
        let log = try analysis("ln(x)").integral(from: 0, to: 1)
        XCTAssertEqual(log.value, -1, accuracy: 1e-8)
        XCTAssertEqual(log.status, .converged)

        let root = try analysis("1/sqrt(x)").integral(from: 0, to: 1)
        XCTAssertEqual(root.value, 2, accuracy: 1e-5)
        XCTAssertEqual(root.status, .converged)

        let sinc = try analysis("sin(x)/x").integral(from: -1, to: 1)
        XCTAssertEqual(sinc.value, 1.8921661407343662, accuracy: 1e-10)
    }

    func testClosedFormsAreRecognized() throws {
        XCTAssertEqual(ClosedForm.recognize(try analysis("x·sin(x)").integral(from: 0, to: .pi).value), "π")
        XCTAssertEqual(ClosedForm.recognize(try analysis("x^2").integral(from: 0, to: 1).value), "1/3")
        XCTAssertEqual(ClosedForm.recognize(try analysis("e^(-x^2)").integral(from: -12, to: 12).value), "√π")
        XCTAssertEqual(ClosedForm.recognize(try analysis("1/(1+x^2)").integral(from: -1, to: 1).value), "π/2")
        XCTAssertEqual(ClosedForm.recognize(-0.75 * .pi), "−3π/4")
        XCTAssertEqual(ClosedForm.recognize(2 * 2.0.squareRoot()), "2√2")
        XCTAssertNil(ClosedForm.recognize(0.7834305107121344), "the sophomore's dream has no simple closed form")
        XCTAssertNil(ClosedForm.recognize(.nan))
    }

    func testDivergentAndUndefinedIntegrals() throws {
        XCTAssertEqual(try analysis("1/x").integral(from: -1, to: 1).status, .divergent)
        XCTAssertEqual(try analysis("1/x^2").integral(from: 0, to: 1).status, .divergent)
        XCTAssertEqual(try analysis("tan(x)").integral(from: 0, to: 3).status, .divergent)
        let undefined = try analysis("ln(x)").integral(from: -1, to: 1)
        XCTAssertEqual(undefined.status, .undefined)
        XCTAssertTrue(undefined.value.isNaN)
        // Infinite right at an endpoint, where only one side can be probed.
        XCTAssertEqual(try analysis("1/ln(x^2 + 1)").integral(from: 0, to: 1).status, .divergent)
    }
}

private func assertClose(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, "counts differ: \(a) vs \(b)", file: file, line: line)
    for (x, y) in zip(a, b) {
        XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line)
    }
}
