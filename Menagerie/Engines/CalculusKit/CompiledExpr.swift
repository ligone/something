import Foundation

/// An expression compiled to a flat program for a small stack machine.
///
/// Walking a tree of indirect enums costs a pointer chase and a reference
/// count per node. Plotting evaluates the same function thousands of times a
/// frame, so it pays to flatten the tree once into postfix instructions and
/// run them over a scratch stack instead.
///
///     let f = CompiledExpr(try MathParser.parse("x·sin(x)"))
///     f(2)   // 1.8185948536513634
public struct CompiledExpr: Sendable {
    enum Instruction: Sendable {
        case constant(Double)
        case variable
        case add, subtract, multiply, divide
        case negate, reciprocal, square, squareRoot
        /// A power with an integer exponent.
        case integerPower(Double)
        /// A power with an exact fractional exponent `p/q`, taking real odd
        /// roots of negative bases.
        case rationalPower(MathNumber)
        /// A power with a real exponent.
        case realPower(Double)
        /// A power with a computed exponent, which is on top of the stack.
        case power
        case function(MathFunction)
    }

    let instructions: [Instruction]
    let stackSize: Int

    public init(_ expression: MathExpr) {
        var instructions: [Instruction] = []
        var depth = 0
        var maximum = 1
        CompiledExpr.emit(expression, into: &instructions, depth: &depth, maximum: &maximum)
        self.instructions = instructions
        self.stackSize = maximum
    }

    /// The value at `x`. Undefined points give NaN or ±∞.
    public func callAsFunction(_ x: Double) -> Double {
        withUnsafeTemporaryAllocation(of: Double.self, capacity: stackSize) { stack in
            run(x, stack)
        }
    }

    /// Values at many points, reusing one scratch stack.
    public func evaluate(_ xs: [Double]) -> [Double] {
        withUnsafeTemporaryAllocation(of: Double.self, capacity: stackSize) { stack in
            xs.map { run($0, stack) }
        }
    }

    private func run(_ x: Double, _ stack: UnsafeMutableBufferPointer<Double>) -> Double {
        var top = -1
        for instruction in instructions {
            switch instruction {
            case let .constant(value):
                top += 1
                stack[top] = value
            case .variable:
                top += 1
                stack[top] = x
            case .add:
                top -= 1
                stack[top] += stack[top + 1]
            case .subtract:
                top -= 1
                stack[top] -= stack[top + 1]
            case .multiply:
                top -= 1
                stack[top] *= stack[top + 1]
            case .divide:
                top -= 1
                stack[top] /= stack[top + 1]
            case .negate:
                stack[top] = -stack[top]
            case .reciprocal:
                stack[top] = 1 / stack[top]
            case .square:
                stack[top] *= stack[top]
            case .squareRoot:
                stack[top] = stack[top].squareRoot()
            case let .integerPower(exponent):
                stack[top] = Foundation.pow(stack[top], exponent)
            case let .rationalPower(exponent):
                stack[top] = MathNumber.power(stack[top], exponent)
            case let .realPower(exponent):
                stack[top] = Foundation.pow(stack[top], exponent)
            case .power:
                top -= 1
                stack[top] = Foundation.pow(stack[top], stack[top + 1])
            case let .function(function):
                stack[top] = function.evaluate(stack[top])
            }
        }
        return top == 0 ? stack[0] : .nan
    }

    // MARK: Compiling

    private static func emit(
        _ expression: MathExpr,
        into program: inout [Instruction],
        depth: inout Int,
        maximum: inout Int
    ) {
        func push(_ instruction: Instruction) {
            program.append(instruction)
            depth += 1
            maximum = max(maximum, depth)
        }
        func combine(_ instruction: Instruction) {
            program.append(instruction)
            depth -= 1
        }

        switch expression {
        case let .number(value):
            push(.constant(value.doubleValue))

        case .variable:
            push(.variable)

        case let .constant(constant):
            push(.constant(constant.value))

        case let .sum(terms):
            guard let first = terms.first else {
                push(.constant(0))
                return
            }
            emit(first, into: &program, depth: &depth, maximum: &maximum)
            for term in terms.dropFirst() {
                // a + (−1)·b compiles to a − b.
                if let positive = MathSimplifier.withoutMinusSign(term) {
                    emit(positive, into: &program, depth: &depth, maximum: &maximum)
                    combine(.subtract)
                } else {
                    emit(term, into: &program, depth: &depth, maximum: &maximum)
                    combine(.add)
                }
            }

        case let .product(factors):
            guard let first = factors.first else {
                push(.constant(1))
                return
            }
            var rest = factors.dropFirst()
            var negated = false
            if first == .minusOne, let second = rest.first {
                negated = true
                rest = rest.dropFirst()
                emit(second, into: &program, depth: &depth, maximum: &maximum)
            } else {
                emit(first, into: &program, depth: &depth, maximum: &maximum)
            }
            for factor in rest {
                // a · b^(−1) compiles to a / b.
                if case let .power(base, .number(exponent)) = factor, exponent.doubleValue == -1 {
                    emit(base, into: &program, depth: &depth, maximum: &maximum)
                    combine(.divide)
                } else {
                    emit(factor, into: &program, depth: &depth, maximum: &maximum)
                    combine(.multiply)
                }
            }
            if negated {
                program.append(.negate)
            }

        case let .power(base, exponent):
            emit(base, into: &program, depth: &depth, maximum: &maximum)
            guard let value = exponent.numberValue else {
                emit(exponent, into: &program, depth: &depth, maximum: &maximum)
                combine(.power)
                return
            }
            if let fraction = value.fraction {
                switch fraction {
                case (1, 1): break
                case (2, 1): program.append(.square)
                case (-1, 1): program.append(.reciprocal)
                case (1, 2): program.append(.squareRoot)
                case let (p, 1): program.append(.integerPower(Double(p)))
                default: program.append(.rationalPower(value))
                }
            } else {
                program.append(.realPower(value.doubleValue))
            }

        case let .function(function, argument):
            emit(argument, into: &program, depth: &depth, maximum: &maximum)
            program.append(.function(function))
        }
    }
}
