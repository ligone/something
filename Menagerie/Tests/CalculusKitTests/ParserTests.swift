import XCTest
@testable import CalculusKit

final class ParserTests: XCTestCase {
    /// Parses `source` and evaluates it at `x`.
    private func value(_ source: String, at x: Double = 0, file: StaticString = #filePath, line: UInt = #line) -> Double {
        do {
            return try MathParser.parse(source).evaluate(at: x)
        } catch {
            XCTFail("\(source) failed to parse: \(error)", file: file, line: line)
            return .nan
        }
    }

    private func parseError(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> MathParseError? {
        do {
            let expression = try MathParser.parse(source)
            XCTFail("\(source) parsed as \(expression) but should have failed", file: file, line: line)
            return nil
        } catch let error as MathParseError {
            return error
        } catch {
            XCTFail("Unexpected error type \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: Precedence and associativity

    func testPrecedence() {
        XCTAssertEqual(value("2+3*4"), 14)
        XCTAssertEqual(value("(2+3)*4"), 20)
        XCTAssertEqual(value("2*3^2"), 18)
        XCTAssertEqual(value("10-4-3"), 3)
        XCTAssertEqual(value("8/4/2"), 1)
        XCTAssertEqual(value("2+3*4^2/8-1"), 7)
    }

    func testPowerIsRightAssociative() {
        XCTAssertEqual(value("2^3^2"), 512)
        XCTAssertEqual(value("(2^3)^2"), 64)
        XCTAssertEqual(value("2**3**2"), 512)
    }

    func testUnaryMinusBindsLooserThanPower() {
        XCTAssertEqual(value("-x^2", at: 3), -9)
        XCTAssertEqual(value("(-x)^2", at: 3), 9)
        XCTAssertEqual(value("-2^2"), -4)
        XCTAssertEqual(value("2^-1"), 0.5)
        XCTAssertEqual(value("e^-x^2", at: 1), exp(-1), accuracy: 1e-15)
        XCTAssertEqual(value("--x", at: 5), 5)
        XCTAssertEqual(value("+x", at: 5), 5)
    }

    // MARK: Numbers and constants

    func testNumbers() {
        XCTAssertEqual(value("42"), 42)
        XCTAssertEqual(value("3.25"), 3.25)
        XCTAssertEqual(value(".5"), 0.5)
        XCTAssertEqual(value("5."), 5)
        XCTAssertEqual(value("1e3"), 1000)
        XCTAssertEqual(value("2.5E-2"), 0.025)
        XCTAssertEqual(value("1e+2"), 100)
    }

    func testIntegerLiteralsAreExact() throws {
        XCTAssertEqual(try MathParser.parse("12"), .integer(12))
        XCTAssertEqual(try MathParser.parse("2.0"), .integer(2))
        XCTAssertEqual(try MathParser.parse("0.5"), .real(0.5))
    }

    func testConstants() {
        XCTAssertEqual(value("pi"), .pi)
        XCTAssertEqual(value("π"), .pi)
        XCTAssertEqual(value("PI"), .pi)
        XCTAssertEqual(value("e"), M_E, accuracy: 1e-15)
        // An `e` without digits after it is Euler's number, not an exponent.
        XCTAssertEqual(value("2e"), 2 * M_E, accuracy: 1e-15)
        XCTAssertEqual(value("2e-x", at: 1), 2 * M_E - 1, accuracy: 1e-15)
    }

    // MARK: Implicit multiplication

    func testImplicitMultiplication() {
        XCTAssertEqual(value("2x", at: 3), 6)
        XCTAssertEqual(value("2x^2", at: 3), 18)
        XCTAssertEqual(value("3sin(x)", at: 1), 3 * sin(1), accuracy: 1e-15)
        XCTAssertEqual(value("x(x+1)", at: 3), 12)
        XCTAssertEqual(value("(x+1)(x-1)", at: 3), 8)
        XCTAssertEqual(value("2pi"), 2 * .pi)
        XCTAssertEqual(value("2π x", at: 2), 4 * .pi)
        XCTAssertEqual(value("xsin(x)", at: 2), 2 * sin(2), accuracy: 1e-15)
        XCTAssertEqual(value("sin(x)cos(x)", at: 2), sin(2) * cos(2), accuracy: 1e-15)
        XCTAssertEqual(value("2|x|", at: -3), 6)
        XCTAssertEqual(value("2√x", at: 9), 6)
        // Juxtaposition has the same precedence as `*`.
        XCTAssertEqual(value("1/2x", at: 4), 2)
    }

    // MARK: Functions and notation

    func testFunctions() {
        let x = 0.37
        let cases: [(String, Double)] = [
            ("sin(x)", sin(x)), ("cos(x)", cos(x)), ("tan(x)", tan(x)),
            ("asin(x)", asin(x)), ("acos(x)", acos(x)), ("atan(x)", atan(x)),
            ("arcsin(x)", asin(x)), ("arccos(x)", acos(x)), ("arctan(x)", atan(x)),
            ("sinh(x)", sinh(x)), ("cosh(x)", cosh(x)), ("tanh(x)", tanh(x)),
            ("exp(x)", exp(x)), ("ln(x)", log(x)), ("log(x)", log10(x)), ("log10(x)", log10(x)),
            ("sqrt(x)", x.squareRoot()), ("abs(-x)", x), ("sgn(-x)", -1), ("sign(x)", 1),
        ]
        for (source, expected) in cases {
            XCTAssertEqual(value(source, at: x), expected, accuracy: 1e-15, source)
        }
    }

    func testPrettyNotationParses() {
        XCTAssertEqual(value("x²", at: 3), 9)
        XCTAssertEqual(value("x³ − 3x", at: 2), 2)
        XCTAssertEqual(value("x⁻¹", at: 4), 0.25)
        XCTAssertEqual(value("2·x", at: 4), 8)
        XCTAssertEqual(value("2×x", at: 4), 8)
        XCTAssertEqual(value("x÷4", at: 2), 0.5)
        XCTAssertEqual(value("√x", at: 16), 4)
        XCTAssertEqual(value("√(x+7)", at: 2), 3)
        XCTAssertEqual(value("sin²(x)", at: 0.5), pow(sin(0.5), 2), accuracy: 1e-15)
        XCTAssertEqual(value("sin⁻¹(x)", at: 0.5), asin(0.5), accuracy: 1e-15)
        XCTAssertEqual(value("|x|", at: -2), 2)
        XCTAssertEqual(value("||x|−3|", at: -1), 2)
        XCTAssertEqual(value("e^(−x²)", at: 1), exp(-1), accuracy: 1e-15)
    }

    func testPrintedResultsParseBack() throws {
        let sources = [
            "sin(x)·x²", "e^(-x²)", "1/(1+x²)", "x^x", "sqrt(x)/2", "tan(x)", "asin(x)",
            "log(x)", "|x - 1|", "x^(1/3)", "2^x", "sin(1/x)", "tanh(x)", "3x^2/7 - pi x",
        ]
        for source in sources {
            let expression = try MathParser.parse(source).simplified()
            for candidate in [expression, expression.derivative(), expression.derivative().derivative()] {
                let reparsed = try MathParser.parse(candidate.description).simplified()
                XCTAssertEqual(reparsed, candidate, "\(candidate) should parse back to itself")
            }
        }
    }

    // MARK: Errors

    func testErrorsCarryPositions() {
        let empty = parseError("   ")
        XCTAssertEqual(empty?.position, 0)

        let missingParen = parseError("sin x")
        XCTAssertEqual(missingParen?.position, 4)
        XCTAssertTrue(missingParen?.message.contains("(") ?? false)

        XCTAssertEqual(parseError("(x+1")?.position, 0)
        XCTAssertEqual(parseError("x+1)")?.position, 3)
        XCTAssertEqual(parseError("x+")?.position, 2)
        XCTAssertEqual(parseError("x+*2")?.position, 2)
        XCTAssertEqual(parseError("2 3")?.position, 2)
        XCTAssertEqual(parseError("y + 1")?.position, 0)
        XCTAssertEqual(parseError("2 + foo(x)")?.position, 4)
        XCTAssertEqual(parseError("1.2.3")?.position, 0)
        XCTAssertEqual(parseError("|x")?.position, 0)
        XCTAssertEqual(parseError("sin()")?.position, 3)
        XCTAssertEqual(parseError("()")?.position, 0)
        XCTAssertEqual(parseError("x & 2")?.position, 2)
        XCTAssertEqual(parseError("max(x, 2)")?.position, 0)
    }

    func testErrorMessagesAreHelpful() {
        XCTAssertEqual(parseError("x+")?.message, "Expected a value after '+'")
        XCTAssertEqual(parseError("x+1)")?.message, "Unmatched ')'")
        XCTAssertEqual(parseError("(x+1")?.message, "This '(' is never closed")
        XCTAssertEqual(parseError("x2")?.message, "Missing an operator before '2'")
        XCTAssertTrue(parseError("t")?.message.contains("x") ?? false)
        XCTAssertEqual(parseError("x+1)")?.description, "Unmatched ')' (column 4)")
    }
}
