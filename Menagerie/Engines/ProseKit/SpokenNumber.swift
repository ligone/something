/// Counts the syllables in a number read aloud the way an English speaker
/// would say it: "1,250" is "one thousand two hundred fifty" (8), "1984" is
/// the year "nineteen eighty-four" (5), and "3.14" is "three point one four" (4).
enum SpokenNumber {
    /// Whether the character is a decimal digit in any script ("7", "٧",
    /// "७"). Other numeric characters, such as "½" or the Chinese numeral
    /// "京" (10¹⁶), are not.
    static func isDigit(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        return scalars.count == 1 && scalars.first?.properties.numericType == .decimal
    }

    /// Syllables in digits with optional thousands separators and a decimal
    /// point. Always at least 1.
    static func syllables(in text: String) -> Int {
        let parts = text.filter { $0 != "," }.split(separator: ".", omittingEmptySubsequences: false)
        var total = 0
        if let whole = parts.first, !whole.isEmpty {
            // "1984" may be a year; "1,984" is a quantity.
            total += integerSyllables(digits(in: whole), mayBeYear: !text.contains(","))
        }
        let fraction = digits(in: parts.dropFirst().joined())
        if !fraction.isEmpty {
            // "point", then each digit on its own.
            total += 1 + fraction.reduce(0) { $0 + ones[$1] }
        }
        return max(total, 1)
    }

    private static func digits(in text: some StringProtocol) -> [Int] {
        text.filter(isDigit).compactMap(\.wholeNumberValue)
    }

    private static func integerSyllables(_ digits: [Int], mayBeYear: Bool) -> Int {
        guard !digits.isEmpty else { return 0 }
        // Leading zeros and very long numbers are read digit by digit.
        if (digits.count > 1 && digits[0] == 0) || digits.count > 12 {
            return digits.reduce(0) { $0 + ones[$1] }
        }
        let value = digits.reduce(0) { $0 * 10 + $1 }
        if mayBeYear, digits.count == 4, let year = yearSyllables(value) {
            return year
        }
        return cardinalSyllables(value)
    }

    /// Four-digit numbers from 1100 to 1999 and from 2010 on are read in
    /// pairs, like years: "nineteen oh five", "twenty twenty-four".
    private static func yearSyllables(_ value: Int) -> Int? {
        guard (1100...1999).contains(value) || (2010...2099).contains(value) else { return nil }
        let high = value / 100
        let low = value % 100
        let lowSyllables: Int
        if low == 0 {
            lowSyllables = 2                        // "hundred"
        } else if low < 10 {
            lowSyllables = 1 + ones[low]            // "oh five"
        } else {
            lowSyllables = below100(low)
        }
        return below100(high) + lowSyllables
    }

    static func cardinalSyllables(_ value: Int) -> Int {
        guard value > 0 else { return ones[0] }
        var remaining = value
        var total = 0
        // Each scale word ("billion", "million", "thousand") has two syllables.
        for scale in [1_000_000_000, 1_000_000, 1_000] where remaining >= scale {
            total += below1000(remaining / scale) + 2
            remaining %= scale
        }
        if remaining > 0 {
            total += below1000(remaining)
        }
        return total
    }

    private static func below1000(_ value: Int) -> Int {
        var total = 0
        if value >= 100 {
            total += ones[value / 100] + 2          // "... hundred"
        }
        if value % 100 > 0 {
            total += below100(value % 100)
        }
        return total
    }

    private static func below100(_ value: Int) -> Int {
        if value < 10 { return ones[value] }
        if value < 20 { return teens[value - 10] }
        let unit = value % 10
        return tens[value / 10 - 2] + (unit == 0 ? 0 : ones[unit])
    }

    /// zero, one, two, three, four, five, six, seven, eight, nine.
    private static let ones = [2, 1, 1, 1, 1, 1, 1, 2, 1, 1]
    /// ten, eleven, twelve, thirteen, …, nineteen.
    private static let teens = [1, 3, 1, 2, 2, 2, 2, 3, 2, 2]
    /// twenty, thirty, forty, fifty, sixty, seventy, eighty, ninety.
    private static let tens = [2, 2, 2, 2, 2, 3, 2, 2]
}
