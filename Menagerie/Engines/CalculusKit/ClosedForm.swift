import Foundation

/// Recognizes numbers that are simple closed forms, such as `π/2`, `1/3` or
/// `√π`, from their decimal values.
///
/// Numerical results can't prove a closed form, but when an integral agrees
/// with `π` to nine digits it's worth saying so. Each candidate constant is
/// divided out and the quotient tested for a fraction with a small
/// denominator, using continued fractions.
public enum ClosedForm {
    private static let constants: [(symbol: String, value: Double)] = [
        ("", 1),
        ("π", Double.pi),
        ("e", MathConstant.e.value),
        ("√2", 2.0.squareRoot()),
        ("√3", 3.0.squareRoot()),
        ("√π", Double.pi.squareRoot()),
        ("π²", Double.pi * Double.pi),
        ("ln(2)", Foundation.log(2.0)),
    ]

    /// A closed form within `tolerance` (relative) of `value`, such as
    /// `"3π/4"`, or nil.
    public static func recognize(_ value: Double, tolerance: Double = 1e-9) -> String? {
        guard value.isFinite else { return nil }
        if value == 0 { return "0" }
        for (symbol, constant) in constants {
            guard let fraction = MathNumber.approximating(value / constant, maxDenominator: 12, tolerance: tolerance)?.fraction,
                  abs(fraction.numerator) <= 144 else { continue }
            return format(numerator: fraction.numerator, denominator: fraction.denominator, symbol: symbol)
        }
        return nil
    }

    private static func format(numerator: Int, denominator: Int, symbol: String) -> String {
        let sign = numerator < 0 ? "−" : ""
        let magnitude = numerator.magnitude
        var text: String
        if symbol.isEmpty {
            text = "\(magnitude)"
        } else if magnitude == 1 {
            text = symbol
        } else {
            text = "\(magnitude)\(symbol)"
        }
        if denominator != 1 {
            text += "/\(denominator)"
        }
        return sign + text
    }
}
