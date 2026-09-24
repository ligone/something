import XCTest
@testable import CalculusKit

final class PlottingTests: XCTestCase {
    private func polylines(_ source: String, over domain: ClosedRange<Double>, visible: ClosedRange<Double> = -4...4) throws -> [[PlotPoint]] {
        let f = CompiledExpr(try MathParser.parse(source).simplified())
        return CurveSampler.polylines(of: { f($0) }, over: domain, count: 1000, visibleRange: visible)
    }

    func testSmoothCurvesStayInOnePiece() throws {
        XCTAssertEqual(try polylines("sin(x)·x", over: -10...10).count, 1)
        XCTAssertEqual(try polylines("e^x", over: -5...20).count, 1)
        // Steep, but continuous.
        XCTAssertEqual(try polylines("tanh(1000x)", over: -5...5).count, 1)
    }

    func testPolesSplitCurves() throws {
        let tangent = try polylines("tan(x)", over: -5...5)
        XCTAssertEqual(tangent.count, 5, "tan has poles at ±π/2 and ±3π/2 in (−5, 5)")
        // Each branch runs right up to its asymptote.
        let middle = tangent[2]
        XCTAssertEqual(middle.first?.x ?? .nan, -.pi / 2, accuracy: 1e-6)
        XCTAssertEqual(middle.last?.x ?? .nan, .pi / 2, accuracy: 1e-6)
        XCTAssertLessThan(middle.first?.y ?? 0, -1e3)
        XCTAssertGreaterThan(middle.last?.y ?? 0, 1e3)

        XCTAssertEqual(try polylines("1/x", over: -3...3.1).count, 2)
    }

    func testJumpsSplitCurves() throws {
        let step = try polylines("sgn(x - 0.25)", over: -3...3)
        let long = step.filter { $0.count > 10 }
        XCTAssertEqual(long.count, 2)
        XCTAssertEqual(long[0].last?.x ?? .nan, 0.25, accuracy: 1e-9)
        XCTAssertEqual(long[1].first?.x ?? .nan, 0.25, accuracy: 1e-9)
    }

    func testDomainEdgesAreReached() throws {
        let circle = try polylines("sqrt(1 - x^2)", over: -2...2)
        XCTAssertEqual(circle.count, 1)
        XCTAssertEqual(circle[0].first?.x ?? .nan, -1, accuracy: 1e-9)
        XCTAssertEqual(circle[0].last?.x ?? .nan, 1, accuracy: 1e-9)

        let logarithm = try polylines("ln(x)", over: -2...2)
        XCTAssertEqual(logarithm.count, 1)
        XCTAssertLessThan(logarithm[0].first?.y ?? 0, -10, "the curve dives toward its asymptote")
    }

    func testTickSteps() {
        XCTAssertEqual(AxisTicks.step(span: 10, targetCount: 10), 1)
        XCTAssertEqual(AxisTicks.step(span: 17, targetCount: 8), 2)
        XCTAssertEqual(AxisTicks.step(span: 0.8, targetCount: 8), 0.1, accuracy: 1e-15)
        XCTAssertEqual(AxisTicks.step(span: 45, targetCount: 8), 5)
        XCTAssertEqual(AxisTicks.step(span: 3000, targetCount: 5), 500)
        XCTAssertEqual(AxisTicks.minorDivisions(for: 2), 4)
        XCTAssertEqual(AxisTicks.minorDivisions(for: 0.5), 5)

        // Every step is 1, 2 or 5 times a power of ten.
        for span in stride(from: 0.001, to: 1e6, by: 0.37).prefix(2000) {
            let step = AxisTicks.step(span: span, targetCount: 8)
            let leading = step / pow(10, floor(log10(step)))
            XCTAssertTrue([1, 2, 5].contains { abs(leading - $0) < 1e-9 }, "step \(step)")
        }
    }

    func testTickValuesAndLabels() {
        XCTAssertEqual(AxisTicks.values(in: -1.2...2.9, step: 1), [-1, 0, 1, 2])
        XCTAssertEqual(AxisTicks.values(in: -0.3...0.31, step: 0.1).count, 7)
        XCTAssertEqual(AxisTicks.values(in: -0.3...0.31, step: 0.1)[3], 0, "zero is exact, never −0 or 1e−17")
        XCTAssertEqual(AxisTicks.label(-1.5, step: 0.5), "−1.5")
        XCTAssertEqual(AxisTicks.label(2, step: 0.5), "2.0")
        XCTAssertEqual(AxisTicks.label(20, step: 10), "20")
        XCTAssertEqual(AxisTicks.label(0, step: 0.1), "0")
        XCTAssertEqual(AxisTicks.label(2_500_000, step: 500_000), "2.5e6")
        XCTAssertEqual(AxisTicks.label(-5e-7, step: 5e-7), "−5e−7")
    }
}
