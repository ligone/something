import Foundation

/// Turns expressions into the notation people write by hand.
///
/// * Minimal parentheses, chosen by precedence.
/// * Juxtaposition where it reads naturally (`2x`, `3x²`, `2π`, `x(x + 1)`)
///   and a middle dot elsewhere (`x·sin(x)`).
/// * Superscripts for integer powers (`x²`, `sin²(x)`), `√` for square roots,
///   `|x|` for absolute values and `π` for pi.
/// * Negative powers and fractional coefficients become quotients:
///   `x^(−1/2)/2` prints as `1/(2√x)`.
/// * A true minus sign (−) instead of a hyphen.
///
/// The output parses back to the same expression with ``MathParser``.
public enum MathPrinter {
    public static func format(_ expression: MathExpr) -> String {
        render(expression).text
    }

    // MARK: Numbers

    /// An integer with a true minus sign.
    public static func integer(_ value: Int) -> String {
        value < 0 ? "−\(value.magnitude)" : "\(value)"
    }

    /// A real number with at most `significantDigits` significant digits,
    /// no trailing zeros, a true minus sign, and `e` notation for very large
    /// or very small magnitudes.
    public static func decimal(_ value: Double, significantDigits: Int = 10) -> String {
        if value.isNaN { return "undefined" }
        if value.isInfinite { return value > 0 ? "∞" : "−∞" }
        let digits = max(1, min(17, significantDigits))
        let magnitude = abs(value)
        var text: String
        if magnitude == magnitude.rounded(), magnitude < 1e15 {
            text = String(format: "%.0f", magnitude)
        } else {
            text = String(format: "%.\(digits)g", magnitude)
            if let marker = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
                let mantissa = text[..<marker]
                let exponent = Int(text[text.index(after: marker)...]) ?? 0
                text = "\(mantissa)e\(exponent)"
            }
        }
        if text == "0" { return "0" }
        return value < 0 ? "−" + text : text
    }

    /// `12` as `¹²`, `-1` as `⁻¹`.
    public static func superscript(_ value: Int) -> String {
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻",
        ]
        return String(String(value).map { digits[$0] ?? $0 })
    }

    /// `2` as `₂`, for labels such as `T₇(x)`.
    public static func subscriptDigits(_ value: Int) -> String {
        let digits: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "-": "₋",
        ]
        return String(String(value).map { digits[$0] ?? $0 })
    }

    // MARK: Rendering

    /// How tightly a rendered piece binds, to decide on parentheses.
    enum Precedence: Int, Comparable {
        case sum = 1, product, power, atom

        static func < (lhs: Precedence, rhs: Precedence) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// What a factor looks like, to decide between juxtaposition and `·`.
    enum Look {
        case number, pi, variable, group, other
    }

    struct Rendered {
        var text: String
        var precedence: Precedence
        var look: Look = .other
    }

    static func render(_ expression: MathExpr) -> Rendered {
        switch expression {
        case let .number(value):
            return renderNumber(value)
        case .variable:
            return Rendered(text: "x", precedence: .atom, look: .variable)
        case let .constant(constant):
            return Rendered(text: constant.symbol, precedence: .atom, look: constant == .pi ? .pi : .other)
        case let .sum(terms):
            return renderSum(terms)
        case let .product(factors):
            return renderProduct(factors)
        case let .power(base, exponent):
            if let value = exponent.numberValue, value.isNegative {
                return renderProduct([expression])
            }
            return renderPower(base, exponent)
        case let .function(function, argument):
            let inner = render(argument).text
            let text = function == .abs ? "|\(inner)|" : "\(function.name)(\(inner))"
            return Rendered(text: text, precedence: .atom)
        }
    }

    static func renderNumber(_ value: MathNumber) -> Rendered {
        if let (numerator, denominator) = value.fraction {
            if denominator == 1 {
                return Rendered(text: integer(numerator), precedence: numerator < 0 ? .product : .atom, look: .number)
            }
            return Rendered(text: "\(integer(numerator))/\(denominator)", precedence: .product, look: .number)
        }
        let real = value.doubleValue
        return Rendered(text: decimal(real), precedence: real < 0 ? .product : .atom, look: .number)
    }

    static func renderSum(_ terms: [MathExpr]) -> Rendered {
        var parts = terms.map(signedTerm)
        // `1 − x²` reads better than `−x² + 1`.
        if parts.count == 2, parts[0].negative, !parts[1].negative {
            parts.swapAt(0, 1)
        }
        var text = ""
        for (index, part) in parts.enumerated() {
            if index == 0 {
                text = part.negative ? "−" + part.text : part.text
            } else {
                text += part.negative ? " − " : " + "
                text += part.text
            }
        }
        return Rendered(text: text, precedence: .sum)
    }

    /// A term's sign, and the text of its magnitude.
    static func signedTerm(_ term: MathExpr) -> (negative: Bool, text: String) {
        if case let .number(value) = term {
            return (value.isNegative, renderNumber(value.magnitude).text)
        }
        if let positive = MathSimplifier.withoutMinusSign(term) {
            return (true, render(positive).text)
        }
        return (false, render(term).text)
    }

    static func renderProduct(_ factors: [MathExpr]) -> Rendered {
        var coefficient = MathNumber.one
        var numerator: [MathExpr] = []
        var denominator: [MathExpr] = []
        for factor in factors {
            if case let .number(value) = factor {
                coefficient *= value
            } else if case let .power(base, .number(exponent)) = factor, exponent.isNegative {
                denominator.append(exponent.doubleValue == -1 ? base : .power(base, .number(-exponent)))
            } else {
                numerator.append(factor)
            }
        }

        var top: [Rendered] = []
        var bottom: [Rendered] = []
        let magnitude = coefficient.magnitude
        if let (p, q) = magnitude.fraction {
            if p != 1 { top.append(renderNumber(MathNumber(p))) }
            if q != 1 { bottom.append(renderNumber(MathNumber(q))) }
        } else if !magnitude.isOne {
            top.append(renderNumber(magnitude))
        }
        top += numerator.map(renderFactor)
        bottom += denominator.map(renderFactor)

        var text = top.isEmpty ? "1" : join(top)
        if !bottom.isEmpty {
            let below = join(bottom)
            text += bottom.count > 1 ? "/(\(below))" : "/\(below)"
        }
        if coefficient.isNegative {
            text = "−" + text
        }
        let look: Look = top.count == 1 && bottom.isEmpty && !coefficient.isNegative ? top[0].look : .other
        return Rendered(text: text, precedence: .product, look: look)
    }

    /// A factor of a product, parenthesized if it is a sum.
    static func renderFactor(_ factor: MathExpr) -> Rendered {
        let rendered = render(factor)
        if rendered.precedence < .product {
            return Rendered(text: "(\(rendered.text))", precedence: .atom, look: .group)
        }
        return rendered
    }

    /// Joins factors, juxtaposing where that reads naturally.
    static func join(_ parts: [Rendered]) -> String {
        guard var text = parts.first?.text else { return "" }
        for index in parts.indices.dropFirst() {
            let left = parts[index - 1]
            let right = parts[index]
            text += juxtaposes(left, right) ? "" : "·"
            text += right.text
        }
        return text
    }

    static func juxtaposes(_ left: Rendered, _ right: Rendered) -> Bool {
        if let first = right.text.first, first.isNumber || first == "." { return false }
        switch (left.look, right.look) {
        case (.number, _):
            return true
        case (.pi, .variable), (.pi, .group), (.variable, .group), (.group, .group):
            return true
        default:
            return false
        }
    }

    static func renderPower(_ base: MathExpr, _ exponent: MathExpr) -> Rendered {
        if let value = exponent.numberValue {
            if value == .half {
                let inner = render(base)
                let operand = inner.precedence == .atom && !inner.text.hasPrefix("−") ? inner.text : "(\(inner.text))"
                return Rendered(text: "√" + operand, precedence: .power)
            }
            if let whole = value.wholeValue, whole >= 2 {
                if case let .function(function, argument) = base, function.usesPrefixPowerNotation {
                    let text = "\(function.name)\(superscript(whole))(\(render(argument).text))"
                    return Rendered(text: text, precedence: .atom, look: .other)
                }
                let baseText = renderBase(base)
                let look: Look
                switch base {
                case .variable: look = .variable
                case .constant(.pi): look = .pi
                default: look = baseText.hasPrefix("(") ? .group : .other
                }
                return Rendered(text: baseText + superscript(whole), precedence: .power, look: look)
            }
        }
        // Caret powers always take a `·` before a following factor, so
        // `x^(3/2)·(x + 1)` never looks like a longer exponent.
        return Rendered(text: "\(renderBase(base))^\(renderExponent(exponent))", precedence: .power)
    }

    static func renderBase(_ base: MathExpr) -> String {
        let rendered = render(base)
        return rendered.precedence == .atom ? rendered.text : "(\(rendered.text))"
    }

    static func renderExponent(_ exponent: MathExpr) -> String {
        let rendered = render(exponent)
        return rendered.precedence == .atom ? rendered.text : "(\(rendered.text))"
    }
}
