import XCTest
@testable import CalculusKit

final class DerivativeTests: XCTestCase {
    /// Functions, each with an interval inside its domain that avoids
    /// singularities and kinks.
    private let battery: [(source: String, domain: ClosedRange<Double>)] = [
        ("x^3 - 3x + 1", -3...3),
        ("sin(x)·x²", -4...4),
        ("e^(-x²)", -3...3),
        ("1/(1 + x²)", -4...4),
        ("ln(x)", 0.2...5),
        ("sqrt(x)", 0.2...5),
        ("x^x", 0.2...3),
        ("tan(x)", -1.3...1.3),
        ("asin(x)", -0.9...0.9),
        ("acos(x/2)", -1.8...1.8),
        ("atan(3x)", -3...3),
        ("sinh(x)·cosh(2x)", -2...2),
        ("tanh(x)^3", -3...3),
        ("log(x^2 + 1)", -3...3),
        ("sin(1/x)", 0.3...2),
        ("x/(x^2 - 4)", -1.5...1.5),
        ("cos(x)^2 - sin(x)", -3...3),
        ("2^x·x", -2...2),
        ("(x^2 + 1)^(3/2)", -2...2),
        ("x^(1/3)", 0.3...3),
        ("|x - 1|·x", 1.2...3),
        ("exp(sin(x))", -3...3),
        ("sqrt(1 - x^2)·asin(x)", -0.9...0.9),
        ("sin(x)^x", 0.3...2.5),
        ("ln(ln(x))", 1.5...5),
    ]

    /// A central difference with Richardson extrapolation: O(h⁴) accurate.
    private func numericDerivative(_ f: (Double) -> Double, at x: Double) -> Double {
        let h = 1e-3 * max(1, abs(x))
        let coarse = (f(x + h) - f(x - h)) / (2 * h)
        let fine = (f(x + h / 2) - f(x - h / 2)) / h
        return (4 * fine - coarse) / 3
    }

    func testSymbolicDerivativesMatchFiniteDifferences() throws {
        for (source, domain) in battery {
            let f = try MathParser.parse(source)
            let derivative = Derivative.of(f)
            for step in 0...20 {
                let x = domain.lowerBound + (domain.upperBound - domain.lowerBound) * Double(step) / 20
                let symbolic = derivative.evaluate(at: x)
                let numeric = numericDerivative({ f.evaluate(at: $0) }, at: x)
                let tolerance = 1e-6 * max(1, abs(numeric))
                XCTAssertEqual(symbolic, numeric, accuracy: tolerance, "d/dx \(source) = \(derivative) at x = \(x)")
            }
        }
    }

    func testSecondDerivativesMatchFiniteDifferences() throws {
        for (source, domain) in battery {
            let f = try MathParser.parse(source)
            let first = Derivative.of(f)
            let second = Derivative.of(f, order: 2)
            for step in 1...9 {
                let x = domain.lowerBound + (domain.upperBound - domain.lowerBound) * Double(step) / 10
                let symbolic = second.evaluate(at: x)
                let numeric = numericDerivative({ first.evaluate(at: $0) }, at: x)
                let tolerance = 1e-5 * max(1, abs(numeric))
                XCTAssertEqual(symbolic, numeric, accuracy: tolerance, "d²/dx² \(source) = \(second) at x = \(x)")
            }
        }
    }

    func testCompiledEvaluationMatchesTreeWalking() throws {
        for (source, domain) in battery {
            let expressions = [try MathParser.parse(source)].flatMap { [$0, $0.simplified(), Derivative.of($0, order: 2)] }
            for expression in expressions {
                let compiled = CompiledExpr(expression)
                let xs = (0...12).map { domain.lowerBound + (domain.upperBound - domain.lowerBound) * Double($0) / 12 }
                let batch = compiled.evaluate(xs)
                for (x, fromBatch) in zip(xs, batch) {
                    let expected = expression.evaluate(at: x)
                    XCTAssertEqual(compiled(x), expected, accuracy: 1e-12 * max(1, abs(expected)), "\(expression) at \(x)")
                    XCTAssertEqual(fromBatch, expected, accuracy: 1e-12 * max(1, abs(expected)), "\(expression) at \(x)")
                }
            }
        }
    }

    func testSimplificationPreservesValues() throws {
        for (source, domain) in battery {
            let raw = try MathParser.parse(source)
            let simplified = raw.simplified()
            for step in 0...10 {
                let x = domain.lowerBound + (domain.upperBound - domain.lowerBound) * Double(step) / 10
                let expected = raw.evaluate(at: x)
                XCTAssertEqual(simplified.evaluate(at: x), expected, accuracy: 1e-12 * max(1, abs(expected)), "\(source) → \(simplified)")
            }
        }
    }

    func testHigherOrderDerivatives() throws {
        let f = try MathParser.parse("x^5")
        XCTAssertEqual(Derivative.of(f, order: 0).description, "x⁵")
        XCTAssertEqual(Derivative.of(f, order: 3).description, "60x²")
        XCTAssertEqual(Derivative.of(f, order: 5).description, "120")
        XCTAssertEqual(Derivative.of(f, order: 6), .zero)

        let sine = try MathParser.parse("sin(x)")
        XCTAssertEqual(Derivative.of(sine, order: 4), sine)
    }

    func testOddRootsOfNegativeNumbers() throws {
        // Once simplified, 1/3 is an exact exponent, so odd roots stay real.
        let cubeRoot = try MathParser.parse("x^(1/3)").simplified()
        XCTAssertEqual(cubeRoot.evaluate(at: -8), -2, accuracy: 1e-15)
        XCTAssertEqual(CompiledExpr(cubeRoot)(-27), -3, accuracy: 1e-14)
        // d/dx x^(1/3) = 1/(3x^(2/3)), which is positive on both sides of 0.
        XCTAssertEqual(Derivative.of(cubeRoot).evaluate(at: -8), 1.0 / 12, accuracy: 1e-15)
    }
}
