/// Parses text such as `3sin(x)·x² − e^(−x)/2` into a ``MathExpr``.
///
/// A Pratt parser: every token has a binding power, and one loop handles all
/// the infix operators. From loosest to tightest:
///
/// | Operators                       | Binding | Associativity |
/// |---------------------------------|---------|---------------|
/// | `+` `−`                         | 10      | left          |
/// | `*` `/` and juxtaposition       | 20      | left          |
/// | prefix `−` `+` `√`              | 25      |               |
/// | `^` and superscripts (`x²`)     | 30      | right         |
///
/// So `-x^2` is `−(x²)`, `2^3^2` is `2^9` and `2x²` is `2·x²`. Juxtaposition
/// multiplies: `2x`, `3sin(x)`, `x(x+1)`, `(x+1)(x−1)` and `2pi` all work.
/// The result is not simplified; call ``MathExpr/simplified()`` for that.
public enum MathParser {
    public static func parse(_ source: String) throws -> MathExpr {
        var parser = Parser(tokens: try MathLexer.tokenize(source))
        return try parser.parseAll()
    }
}

private enum BindingPower {
    static let sum = 10
    static let product = 20
    static let prefix = 25
    static let power = 30
}

private struct Parser {
    let tokens: [MathToken]
    var index = 0
    /// How many `|…|` groups are open. Inside one, a `|` after an operand
    /// closes the group instead of starting a new one by juxtaposition.
    var openBars = 0

    init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    var current: MathToken { tokens[index] }

    mutating func advance() -> MathToken {
        let token = tokens[index]
        if index < tokens.count - 1 { index += 1 }
        return token
    }

    mutating func parseAll() throws -> MathExpr {
        guard current.kind != .end else {
            throw MathParseError("Type a function of x, such as x·sin(x)", position: 0)
        }
        let expression = try parseExpression(0)
        switch current.kind {
        case .end:
            return expression
        case .rightParen:
            throw MathParseError("Unmatched ')'", position: current.position)
        case .bar:
            throw MathParseError("Unmatched '|'", position: current.position)
        default:
            throw MathParseError("Unexpected '\(current.text)'", position: current.position, length: current.length)
        }
    }

    // MARK: The Pratt loop

    mutating func parseExpression(_ rightBindingPower: Int) throws -> MathExpr {
        var left = try parsePrefix()
        while let power = infixBindingPower(current.kind), power > rightBindingPower {
            left = try parseInfix(left)
        }
        return left
    }

    func infixBindingPower(_ kind: MathToken.Kind) -> Int? {
        switch kind {
        case .plus, .minus:
            return BindingPower.sum
        case .times, .divide:
            return BindingPower.product
        case .caret, .superscript:
            return BindingPower.power
        case .number, .variable, .constant, .function, .leftParen, .root:
            return BindingPower.product // juxtaposition
        case .bar:
            return openBars > 0 ? nil : BindingPower.product
        case .rightParen, .end:
            return nil
        }
    }

    mutating func parseInfix(_ left: MathExpr) throws -> MathExpr {
        let token = current
        switch token.kind {
        case .plus:
            _ = advance()
            return .sum([left, try parseOperand(BindingPower.sum, after: token)])
        case .minus:
            _ = advance()
            let right = try parseOperand(BindingPower.sum, after: token)
            return .sum([left, .product([.minusOne, right])])
        case .times:
            _ = advance()
            return .product([left, try parseOperand(BindingPower.product, after: token)])
        case .divide:
            _ = advance()
            let right = try parseOperand(BindingPower.product, after: token)
            return .product([left, .power(right, .minusOne)])
        case .caret:
            _ = advance()
            // One less than its own power makes `^` right-associative.
            return .power(left, try parseOperand(BindingPower.power - 1, after: token))
        case let .superscript(exponent):
            _ = advance()
            return .power(left, .integer(exponent))
        case .number:
            throw MathParseError("Missing an operator before '\(token.text)'", position: token.position, length: token.length)
        default:
            // Juxtaposition: the next token starts an operand of its own.
            return .product([left, try parseExpression(BindingPower.product)])
        }
    }

    // MARK: Operands

    /// Parses the operand after an operator, with a helpful message if
    /// there isn't one.
    mutating func parseOperand(_ bindingPower: Int, after operatorToken: MathToken) throws -> MathExpr {
        guard canStartOperand(current.kind) else {
            throw MathParseError(
                "Expected a value after '\(operatorToken.text)'",
                position: current.position,
                length: current.length
            )
        }
        return try parseExpression(bindingPower)
    }

    func canStartOperand(_ kind: MathToken.Kind) -> Bool {
        switch kind {
        case .number, .variable, .constant, .function, .leftParen, .bar, .root, .minus, .plus:
            return true
        default:
            return false
        }
    }

    mutating func parsePrefix() throws -> MathExpr {
        let token = advance()
        switch token.kind {
        case let .number(value):
            return .number(value)
        case .variable:
            return .variable
        case let .constant(constant):
            return .constant(constant)
        case .minus:
            return .product([.minusOne, try parseOperand(BindingPower.prefix, after: token)])
        case .plus:
            return try parseOperand(BindingPower.prefix, after: token)
        case .root:
            return .function(.sqrt, try parseOperand(BindingPower.prefix, after: token))
        case .leftParen:
            return try parseGroup(openedBy: token)
        case .bar:
            return try parseAbsoluteValue(openedBy: token)
        case let .function(function):
            return try parseCall(of: function, named: token)
        case .superscript:
            throw MathParseError("A superscript needs something to raise to that power", position: token.position, length: token.length)
        case .rightParen:
            throw MathParseError("Expected a value before ')'", position: token.position)
        case .end:
            throw MathParseError("Expected a value", position: token.position)
        default:
            throw MathParseError("Expected a value before '\(token.text)'", position: token.position, length: token.length)
        }
    }

    /// `( … )`, after the opening parenthesis.
    mutating func parseGroup(openedBy open: MathToken) throws -> MathExpr {
        if current.kind == .rightParen {
            throw MathParseError("Empty parentheses", position: open.position, length: 2)
        }
        if current.kind == .end {
            throw MathParseError("This '(' is never closed", position: open.position)
        }
        let savedBars = openBars
        openBars = 0
        let inner = try parseExpression(0)
        openBars = savedBars
        guard current.kind == .rightParen else {
            throw MathParseError("This '(' is never closed", position: open.position)
        }
        _ = advance()
        return inner
    }

    /// `| … |`, after the opening bar.
    mutating func parseAbsoluteValue(openedBy open: MathToken) throws -> MathExpr {
        // `||x| − 1|` nests; `||` followed by nothing to measure is empty.
        if current.kind == .bar, !canStartOperand(tokens[min(index + 1, tokens.count - 1)].kind) {
            throw MathParseError("Empty absolute value bars", position: open.position, length: 2)
        }
        if current.kind == .end {
            throw MathParseError("This '|' is never closed", position: open.position)
        }
        openBars += 1
        let inner = try parseExpression(0)
        openBars -= 1
        guard current.kind == .bar else {
            throw MathParseError("This '|' is never closed", position: open.position)
        }
        _ = advance()
        return .function(.abs, inner)
    }

    /// `sin(…)`, and the traditional `sin²(…)` and `sin⁻¹(…)`, after the name.
    mutating func parseCall(of function: MathFunction, named name: MathToken) throws -> MathExpr {
        var function = function
        var exponent: Int?
        var spelled = name.text
        if case let .superscript(value) = current.kind {
            spelled += current.text
            _ = advance()
            if value == -1 {
                let inverses: [MathFunction: MathFunction] = [.sin: .asin, .cos: .acos, .tan: .atan]
                guard let inverse = inverses[function] else {
                    throw MathParseError(
                        "Write 1/\(name.text)(…) for a reciprocal; ⁻¹ only means an inverse for sin, cos and tan",
                        position: name.position,
                        length: spelled.count
                    )
                }
                function = inverse
            } else if value >= 0 {
                exponent = value
            } else {
                throw MathParseError("Write 1/\(name.text)(…) for negative powers", position: name.position, length: spelled.count)
            }
        }

        guard current.kind == .leftParen else {
            throw MathParseError(
                "Expected '(' after \(spelled), as in \(spelled)(x)",
                position: current.position,
                length: current.length
            )
        }
        let open = advance()
        if current.kind == .rightParen {
            throw MathParseError("\(name.text)(…) needs an argument", position: open.position, length: 2)
        }
        let argument = try parseGroup(openedBy: open)
        let call = MathExpr.function(function, argument)
        if let exponent {
            return .power(call, .integer(exponent))
        }
        return call
    }
}
