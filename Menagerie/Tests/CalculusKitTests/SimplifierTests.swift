import XCTest
@testable import CalculusKit

final class SimplifierTests: XCTestCase {
    private func simplified(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        do {
            return try MathParser.parse(source).simplified().description
        } catch {
            XCTFail("\(source): \(error)", file: file, line: line)
            return ""
        }
    }

    private func derivative(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        do {
            return try MathParser.parse(source).derivative().description
        } catch {
            XCTFail("\(source): \(error)", file: file, line: line)
            return ""
        }
    }

    // MARK: Derivatives a human would write

    func testClassicDerivatives() {
        XCTAssertEqual(derivative("x^3"), "3x²")
        XCTAssertEqual(derivative("sin(x)·x²"), "x²·cos(x) + 2x·sin(x)")
        XCTAssertEqual(derivative("x³ − 3x"), "3x² − 3")
        XCTAssertEqual(derivative("e^(-x²)"), "−2x·e^(−x²)")
        XCTAssertEqual(derivative("ln(x)"), "1/x")
        XCTAssertEqual(derivative("1/(1+x²)"), "−2x/(x² + 1)²")
        XCTAssertEqual(derivative("sin(1/x)"), "−cos(1/x)/x²")
        XCTAssertEqual(derivative("x^x"), "x^x·(ln(x) + 1)")
        XCTAssertEqual(derivative("tanh(x)"), "1/cosh²(x)")
        XCTAssertEqual(derivative("tan(x)"), "1/cos²(x)")
        XCTAssertEqual(derivative("sqrt(x)"), "1/(2√x)")
        XCTAssertEqual(derivative("asin(x)"), "1/√(1 − x²)")
        XCTAssertEqual(derivative("atan(x)"), "1/(x² + 1)")
        XCTAssertEqual(derivative("log(x)"), "1/(x·ln(10))")
        XCTAssertEqual(derivative("2^x"), "2^x·ln(2)")
        XCTAssertEqual(derivative("|x|"), "sgn(x)")
        XCTAssertEqual(derivative("x·sin(x)"), "x·cos(x) + sin(x)")
        XCTAssertEqual(derivative("sin(x)cos(x)"), "cos²(x) − sin²(x)")
        XCTAssertEqual(derivative("(x^2+1)^3"), "6x(x² + 1)²")
        XCTAssertEqual(derivative("5"), "0")
        XCTAssertEqual(derivative("x^pi"), "π·x^(π − 1)")
    }

    // MARK: Simplification rules

    func testConstantFolding() {
        XCTAssertEqual(simplified("2+3*4"), "14")
        XCTAssertEqual(simplified("1/3 + 1/6"), "1/2")
        XCTAssertEqual(simplified("2^10"), "1024")
        XCTAssertEqual(simplified("4^(1/2)"), "2")
        XCTAssertEqual(simplified("8^(2/3)"), "4")
        XCTAssertEqual(simplified("(-8)^(1/3)"), "−2")
        XCTAssertEqual(simplified("sqrt(2)"), "√2")
        XCTAssertEqual(simplified("0.1 + 0.2"), "0.3")
        // Too large for a Double: kept symbolic rather than folded to ∞.
        XCTAssertEqual(simplified("2^10000"), "2¹⁰⁰⁰⁰")
        // Too large for an exact Int: an inexact real.
        XCTAssertEqual(simplified("2^100"), "1.2676506e30")
        XCTAssertEqual(simplified("2^62"), "4611686018427387904")
    }

    func testIdentities() {
        XCTAssertEqual(simplified("0 + x"), "x")
        XCTAssertEqual(simplified("1·x"), "x")
        XCTAssertEqual(simplified("0·sin(x)"), "0")
        XCTAssertEqual(simplified("x^1"), "x")
        XCTAssertEqual(simplified("x^0"), "1")
        XCTAssertEqual(simplified("-(-x)"), "x")
        XCTAssertEqual(simplified("1^x"), "1")
    }

    func testFlatteningAndLikeTerms() {
        XCTAssertEqual(simplified("2x + 3x"), "5x")
        XCTAssertEqual(simplified("x + (x + (x + 1))"), "3x + 1")
        XCTAssertEqual(simplified("x - (x - 1)"), "1")
        XCTAssertEqual(simplified("sin(x) + 2sin(x)"), "3sin(x)")
        XCTAssertEqual(simplified("x^2 + 1 + x + x^2"), "2x² + x + 1")
        XCTAssertEqual(simplified("2(x+1) - 2x"), "2")
    }

    func testCombiningPowers() {
        XCTAssertEqual(simplified("x·x"), "x²")
        XCTAssertEqual(simplified("x^2·x^3"), "x⁵")
        XCTAssertEqual(simplified("x^sin(x)·x^2"), "x^(sin(x) + 2)")
        XCTAssertEqual(simplified("e^x·e^(2x)"), "e^(3x)")
        XCTAssertEqual(simplified("(x^2)^3"), "x⁶")
        XCTAssertEqual(simplified("(2x)^2"), "4x²")
        XCTAssertEqual(simplified("sqrt(x)·sqrt(x)"), "x")
        XCTAssertEqual(simplified("sqrt(x^2)"), "|x|")
        XCTAssertEqual(simplified("|x|^2"), "x²")
    }

    func testCancellingQuotients() {
        XCTAssertEqual(simplified("x/x"), "1")
        XCTAssertEqual(simplified("x^2/x"), "x")
        XCTAssertEqual(simplified("(x·sin(x))/x"), "sin(x)")
        XCTAssertEqual(simplified("6x/(3x^2)"), "2/x")
        XCTAssertEqual(simplified("(x+1)/(x+1)^3"), "1/(x + 1)²")
    }

    func testNegatives() {
        XCTAssertEqual(simplified("-(x - 1)"), "1 − x")
        XCTAssertEqual(simplified("(-x)·(-x)"), "x²")
        XCTAssertEqual(simplified("-x/-2"), "x/2")
        XCTAssertEqual(simplified("sin(-x)"), "−sin(x)")
        XCTAssertEqual(simplified("cos(-2x)"), "cos(2x)")
        XCTAssertEqual(simplified("|-3x|"), "3|x|")
    }

    func testSpecialValues() {
        XCTAssertEqual(simplified("sin(pi)"), "0")
        XCTAssertEqual(simplified("cos(pi)"), "−1")
        XCTAssertEqual(simplified("sin(3pi/2)"), "−1")
        XCTAssertEqual(simplified("ln(e)"), "1")
        XCTAssertEqual(simplified("ln(e^(2x))"), "2x")
        XCTAssertEqual(simplified("log(1000)"), "3")
        XCTAssertEqual(simplified("exp(0)"), "1")
        XCTAssertEqual(simplified("atan(1)"), "π/4")
        XCTAssertEqual(simplified("sin(x)^2 + cos(x)^2 - cos(x)^2"), "sin²(x)")
    }

    func testFixpoint() throws {
        for source in ["x^x", "sin(x)·x²", "e^(-x²)/(1 + x²)", "sqrt(4x)·sqrt(x)", "ln(x)^2/x"] {
            let once = try MathParser.parse(source).simplified()
            XCTAssertEqual(once.simplified(), once, source)
            XCTAssertEqual(MathSimplifier.pass(once), once, "\(source) should be a fixpoint")
        }
    }

    // MARK: Printing

    func testPrinting() {
        XCTAssertEqual(simplified("2*x"), "2x")
        XCTAssertEqual(simplified("3*x^2"), "3x²")
        XCTAssertEqual(simplified("x*sin(x)"), "x·sin(x)")
        XCTAssertEqual(simplified("2*pi*x"), "2πx")
        XCTAssertEqual(simplified("x*(x+1)"), "x(x + 1)")
        XCTAssertEqual(simplified("(x+1)*(x+2)"), "(x + 1)(x + 2)")
        XCTAssertEqual(simplified("sin(x)^2"), "sin²(x)")
        XCTAssertEqual(simplified("ln(x)^2"), "ln(x)²")
        XCTAssertEqual(simplified("x^(-2)"), "1/x²")
        XCTAssertEqual(simplified("x^(3/2)"), "x^(3/2)")
        XCTAssertEqual(simplified("sqrt(x + 1)"), "√(x + 1)")
        XCTAssertEqual(simplified("abs(x - 1)"), "|x − 1|")
        XCTAssertEqual(simplified("x^12"), "x¹²")
        XCTAssertEqual(simplified("0.5x"), "0.5x")
        XCTAssertEqual(simplified("x/3 - 2/3"), "x/3 − 2/3")
        XCTAssertEqual(simplified("1 - x^2"), "1 − x²")
        XCTAssertEqual(simplified("e^(2x)"), "e^(2x)")
        XCTAssertEqual(simplified("2·3^x"), "2·3^x")
    }

    func testNumberFormatting() {
        XCTAssertEqual(MathPrinter.decimal(0.30000000000000004), "0.3")
        XCTAssertEqual(MathPrinter.decimal(-2.5), "−2.5")
        XCTAssertEqual(MathPrinter.decimal(1e-7), "1e-7")
        XCTAssertEqual(MathPrinter.decimal(3.14159265, significantDigits: 4), "3.142")
        XCTAssertEqual(MathPrinter.decimal(1234567), "1234567")
        XCTAssertEqual(MathPrinter.decimal(.nan), "undefined")
        XCTAssertEqual(MathPrinter.superscript(-12), "⁻¹²")
        XCTAssertEqual(MathPrinter.subscriptDigits(7), "₇")
    }

    func testExactNumbers() {
        XCTAssertEqual(MathNumber(6, -4), MathNumber(-3, 2))
        XCTAssertEqual(MathNumber(1, 3) + MathNumber(1, 6), MathNumber(1, 2))
        XCTAssertEqual(MathNumber(2, 3) * MathNumber(9, 4), MathNumber(3, 2))
        XCTAssertEqual(MathNumber(8).raised(to: MathNumber(-2, 3)), MathNumber(1, 4))
        XCTAssertNil(MathNumber(2).raised(to: .half))
        XCTAssertEqual(MathNumber.approximating(0.1666666666666667), MathNumber(1, 6))
        XCTAssertNil(MathNumber.approximating(Double.pi))
        // Overflow falls back to an inexact real instead of trapping.
        let huge = MathNumber(Int.max / 2) * MathNumber(4)
        XCTAssertFalse(huge.isExact)
        XCTAssertEqual(huge.doubleValue, Double(Int.max / 2) * 4)
    }
}
