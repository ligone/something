/// Why a piece of text isn't a valid expression, and where.
public struct MathParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    /// Where the problem starts, counted in characters from the start of the
    /// input. It equals the input's length when the input ended too soon.
    public var position: Int
    /// How many characters the problem spans; at least 1.
    public var length: Int

    public init(_ message: String, position: Int, length: Int = 1) {
        self.message = message
        self.position = position
        self.length = max(1, length)
    }

    public var description: String {
        "\(message) (column \(position + 1))"
    }
}

/// One lexical unit of an expression.
struct MathToken: Equatable {
    enum Kind: Equatable {
        case number(MathNumber)
        case variable
        case constant(MathConstant)
        case function(MathFunction)
        case plus, minus, times, divide, caret
        /// An exponent written in superscript digits, such as `²` or `⁻¹`.
        case superscript(Int)
        case leftParen, rightParen
        /// `|`, which opens or closes an absolute value.
        case bar
        /// `√`, a prefix square root.
        case root
        case end
    }

    var kind: Kind
    var position: Int
    var length: Int
    /// The characters the token came from, for error messages.
    var text: String
}

/// Splits source text into tokens.
///
/// Besides ASCII it accepts the notation ``MathPrinter`` produces (`·`, `−`,
/// `π`, `√`, superscript exponents), so any printed result can be pasted back
/// in as input. Runs of letters are split into known names, longest first, so
/// `2pix` reads as `2 · π · x` and `xsin(x)` as `x · sin(x)`.
enum MathLexer {
    static func tokenize(_ source: String) throws -> [MathToken] {
        let characters = Array(source)
        var tokens: [MathToken] = []
        var index = 0

        func emit(_ kind: MathToken.Kind, from start: Int) {
            let text = String(characters[start..<index])
            tokens.append(MathToken(kind: kind, position: start, length: index - start, text: text))
        }

        while index < characters.count {
            let character = characters[index]
            let start = index

            if character.isWhitespace {
                index += 1
            } else if character.isASCII, character.isNumber || character == "." {
                let number = try lexNumber(characters, &index)
                emit(.number(number), from: start)
            } else if character.isASCII, character.isLetter {
                while index < characters.count, characters[index].isASCII, characters[index].isLetter {
                    index += 1
                }
                let word = String(characters[start..<index]).lowercased()
                for (offset, kind, length) in try split(word, at: start) {
                    let text = String(characters[(start + offset)..<(start + offset + length)])
                    tokens.append(MathToken(kind: kind, position: start + offset, length: length, text: text))
                }
                // `log10(x)` is a common spelling of the base-10 logarithm.
                if word.hasSuffix("log"), index + 1 < characters.count,
                   characters[index] == "1", characters[index + 1] == "0" {
                    index += 2
                    tokens[tokens.count - 1].length += 2
                    tokens[tokens.count - 1].text += "10"
                }
            } else if superscriptDigits[character] != nil || character == "⁻" {
                let value = try lexSuperscript(characters, &index)
                emit(.superscript(value), from: start)
            } else {
                index += 1
                switch character {
                case "+":
                    emit(.plus, from: start)
                case "-", "−", "–", "—":
                    emit(.minus, from: start)
                case "*":
                    if index < characters.count, characters[index] == "*" {
                        index += 1
                        emit(.caret, from: start)
                    } else {
                        emit(.times, from: start)
                    }
                case "·", "⋅", "×", "∙", "•":
                    emit(.times, from: start)
                case "/", "÷", "∕":
                    emit(.divide, from: start)
                case "^":
                    emit(.caret, from: start)
                case "(":
                    emit(.leftParen, from: start)
                case ")":
                    emit(.rightParen, from: start)
                case "|":
                    emit(.bar, from: start)
                case "√":
                    emit(.root, from: start)
                case "π":
                    emit(.constant(.pi), from: start)
                case ",":
                    throw MathParseError("Functions here take a single argument", position: start)
                default:
                    throw MathParseError("Unexpected character '\(character)'", position: start)
                }
            }
        }

        tokens.append(MathToken(kind: .end, position: characters.count, length: 1, text: ""))
        return tokens
    }

    // MARK: Numbers

    private static func lexNumber(_ characters: [Character], _ index: inout Int) throws -> MathNumber {
        let start = index
        func isDigit(_ offset: Int) -> Bool {
            offset < characters.count && characters[offset].isASCII && characters[offset].isNumber
        }

        var isInteger = true
        while isDigit(index) { index += 1 }
        if index < characters.count, characters[index] == "." {
            isInteger = false
            index += 1
            while isDigit(index) { index += 1 }
        }
        // An exponent needs digits after the `e`, so `2e` still means 2·e.
        if index < characters.count, characters[index] == "e" || characters[index] == "E" {
            if isDigit(index + 1) {
                isInteger = false
                index += 1
                while isDigit(index) { index += 1 }
            } else if index + 1 < characters.count,
                      characters[index + 1] == "+" || characters[index + 1] == "-",
                      isDigit(index + 2) {
                isInteger = false
                index += 2
                while isDigit(index) { index += 1 }
            }
        }

        let text = String(characters[start..<index])
        if index < characters.count, characters[index] == "." {
            while index < characters.count, characters[index] == "." || isDigit(index) { index += 1 }
            let whole = String(characters[start..<index])
            throw MathParseError("Malformed number '\(whole)'", position: start, length: index - start)
        }
        guard text != ".", let value = Double(text) else {
            throw MathParseError("Malformed number '\(text)'", position: start, length: text.count)
        }
        if isInteger, let integer = Int(text) {
            return MathNumber(integer)
        }
        // Whole numbers written as `2.0` or `1e3` are still exact.
        if value.rounded() == value, abs(value) < 9.0e15 {
            return MathNumber(Int(value))
        }
        return MathNumber(real: value)
    }

    // MARK: Superscripts

    static let superscriptDigits: [Character: Int] = [
        "⁰": 0, "¹": 1, "²": 2, "³": 3, "⁴": 4, "⁵": 5, "⁶": 6, "⁷": 7, "⁸": 8, "⁹": 9,
    ]

    private static func lexSuperscript(_ characters: [Character], _ index: inout Int) throws -> Int {
        let start = index
        var negative = false
        if characters[index] == "⁻" {
            negative = true
            index += 1
        }
        var value = 0
        var digits = 0
        while index < characters.count, let digit = superscriptDigits[characters[index]] {
            value = min(value * 10 + digit, 1_000_000)
            digits += 1
            index += 1
        }
        guard digits > 0 else {
            throw MathParseError("A superscript minus needs digits after it", position: start, length: index - start)
        }
        return negative ? -value : value
    }

    // MARK: Names

    private static let names: [(String, MathToken.Kind)] = {
        var table: [(String, MathToken.Kind)] = [
            ("x", .variable),
            ("pi", .constant(.pi)),
            ("e", .constant(.e)),
            ("arcsin", .function(.asin)),
            ("arccos", .function(.acos)),
            ("arctan", .function(.atan)),
            ("sgn", .function(.sign)),
        ]
        for function in MathFunction.allCases {
            table.append((function.rawValue, .function(function)))
        }
        // Longest first, so `sinh` wins over `sin` and `exp` over `e`.
        return table.sorted { $0.0.count > $1.0.count }
    }()

    /// Splits a run of letters into known names: `(offset, kind, length)`.
    private static func split(_ word: String, at position: Int) throws -> [(Int, MathToken.Kind, Int)] {
        let letters = Array(word)
        var pieces: [(Int, MathToken.Kind, Int)] = []
        var offset = 0
        while offset < letters.count {
            let rest = String(letters[offset...])
            guard let (name, kind) = names.first(where: { rest.hasPrefix($0.0) }) else {
                if rest.count == 1 {
                    throw MathParseError(
                        "Unknown variable '\(rest)'. Functions here are functions of x",
                        position: position + offset
                    )
                }
                throw MathParseError("Unknown name '\(rest)'", position: position + offset, length: rest.count)
            }
            pieces.append((offset, kind, name.count))
            offset += name.count
        }
        return pieces
    }
}
