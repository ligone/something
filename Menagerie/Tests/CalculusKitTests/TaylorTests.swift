import XCTest
@testable import CalculusKit

final class TaylorTests: XCTestCase {
    private func series(_ source: String, at center: Double = 0, order: Int = 12) throws -> TaylorSeries {
        TaylorSeries(try MathParser.parse(source), at: center, order: order)
    }

    private func factorial(_ n: Int) -> Double {
        (1...max(1, n)).reduce(1.0) { $0 * Double($1) }
    }

    func testExponentialCoefficientsAreInverseFactorials() throws {
        let exponential = try series("e^x")
        XCTAssertEqual(exponential.order, 12)
        for n in 0...12 {
            XCTAssertEqual(exponential.coefficients[n], 1 / factorial(n), accuracy: 1e-15 / factorial(n), "n = \(n)")
        }
    }

    func testSineAndCosineSeries() throws {
        let sine = try series("sin(x)")
        let cosine = try series("cos(x)")
        for n in 0...12 {
            let sineExpected: Double = n % 2 == 0 ? 0 : (n % 4 == 1 ? 1 : -1) / factorial(n)
            let cosineExpected: Double = n % 2 == 1 ? 0 : (n % 4 == 0 ? 1 : -1) / factorial(n)
            XCTAssertEqual(sine.coefficients[n], sineExpected, accuracy: 1e-16, "sin, n = \(n)")
            XCTAssertEqual(cosine.coefficients[n], cosineExpected, accuracy: 1e-16, "cos, n = \(n)")
        }
        // T₁₁ is within the Lagrange bound |x|¹³/13! of sin(x).
        for x in stride(from: -3.0, through: 3.0, by: 0.25) {
            let bound = pow(abs(x), 13) / factorial(13) + 1e-15
            XCTAssertEqual(sine.evaluate(at: x, order: 12), sin(x), accuracy: bound, "x = \(x)")
        }
    }

    func testSeriesMatchSymbolicDerivatives() throws {
        let cases: [(String, Double)] = [
            ("x^3 - 2x", 1.5), ("sin(x)·x^2", 0.7), ("e^(-x^2)", 0.4), ("1/(1 + x^2)", -1.2),
            ("ln(x)", 2), ("sqrt(x)", 3), ("x^x", 1.3), ("tan(x)", 0.5), ("asin(x)", 0.3),
            ("acos(x)", -0.2), ("atan(2x)", 0.6), ("tanh(x)", -0.8), ("log(x)", 4), ("2^x", 1),
            ("|x - 2|", 0.5), ("x^(1/3)", -8), ("cosh(x)·sinh(x)", 0.3),
        ]
        for (source, center) in cases {
            let expression = try MathParser.parse(source)
            let taylor = TaylorSeries(expression, at: center, order: 4)
            for order in 0...4 {
                let symbolic = Derivative.of(expression, order: order).evaluate(at: center)
                XCTAssertEqual(taylor.derivative(order), symbolic, accuracy: 1e-9 * max(1, abs(symbolic)), "\(source) derivative \(order) at \(center)")
            }
        }
    }

    func testPolynomialsAreTheirOwnSeries() throws {
        let cubic = try series("2x^3 - x + 5", at: 1, order: 6)
        for x in [-2.0, 0, 1.5, 4] {
            XCTAssertEqual(cubic.evaluate(at: x), 2 * x * x * x - x + 5, accuracy: 1e-12)
        }
        XCTAssertEqual(cubic.coefficients[4...].allSatisfy { $0 == 0 }, true)
    }

    func testTangentSeries() throws {
        let tangent = try series("tan(x)", order: 9)
        let expected = [0, 1, 0, 1.0 / 3, 0, 2.0 / 15, 0, 17.0 / 315, 0, 62.0 / 2835]
        for (n, value) in expected.enumerated() {
            XCTAssertEqual(tangent.coefficients[n], value, accuracy: 1e-15, "n = \(n)")
        }
    }

    func testLogarithmSeries() throws {
        let logarithm = try series("ln(1 + x)", order: 8)
        for n in 1...8 {
            let expected = (n % 2 == 1 ? 1.0 : -1.0) / Double(n)
            XCTAssertEqual(logarithm.coefficients[n], expected, accuracy: 1e-15)
        }
    }

    func testUndefinedExpansions() throws {
        XCTAssertFalse(try series("sqrt(x)").isDefined(through: 1))
        XCTAssertFalse(try series("|x|").isDefined(through: 1))
        XCTAssertTrue(try series("|x|", at: 2).isDefined(through: 12))
        XCTAssertFalse(try series("ln(x)").isDefined(through: 0))
        XCTAssertEqual(try series("sqrt(x)").polynomialDescription(order: 3), "undefined")
    }

    func testPolynomialDescriptions() throws {
        XCTAssertEqual(try series("sin(x)").polynomialDescription(order: 7), "x − x³/6 + x⁵/120 − x⁷/5040")
        XCTAssertEqual(try series("e^x").polynomialDescription(order: 3), "1 + x + x²/2 + x³/6")
        XCTAssertEqual(try series("tan(x)").polynomialDescription(order: 7), "x + x³/3 + 2x⁵/15 + 17x⁷/315")
        XCTAssertEqual(try series("x^2", at: 1).polynomialDescription(), "1 + 2(x − 1) + (x − 1)²")
        XCTAssertEqual(try series("cos(x)", at: -1).polynomialDescription(order: 1, significantDigits: 4), "0.5403 + 0.8415(x + 1)")
        XCTAssertEqual(try series("sin(x)").polynomialDescription(order: 0), "0")
    }
}
