import Foundation

/// A point on a sampled curve.
public struct PlotPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Samples functions for plotting, splitting curves wherever they must not
/// be joined.
///
/// A naive plot joins consecutive samples with straight lines, which draws
/// false vertical lines through the poles of `1/x` and `tan(x)` and bridges
/// the gaps in `√x` or `ln(x)`. This sampler breaks the polyline at:
///
/// * undefined values, locating the edge of the domain by bisection so that
///   `√(1 − x²)` still reaches the axis;
/// * jumps: when neighbouring samples differ by a few percent of the visible
///   height, it bisects toward the change. A continuous but steep curve's
///   rise shrinks with the interval, while a pole's or a step's does not.
///
/// Curves stop right at an asymptote instead of one sample short of it.
public enum CurveSampler {
    /// Polylines for `f` over `domain`: consecutive points in each should be
    /// joined, and separate polylines should not.
    ///
    /// - Parameters:
    ///   - count: The number of intervals; one per point of plot width works
    ///     well.
    ///   - visibleRange: The y-range on screen, which decides what counts as a
    ///     jump and lets off-screen stretches skip the jump test.
    public static func polylines(
        of f: (Double) -> Double,
        over domain: ClosedRange<Double>,
        count: Int,
        visibleRange: ClosedRange<Double>
    ) -> [[PlotPoint]] {
        let intervals = max(2, count)
        let lower = domain.lowerBound
        let upper = domain.upperBound
        let step = (upper - lower) / Double(intervals)
        // A continuous curve rarely climbs this much between neighboring
        // samples, so larger steps are worth a closer look.
        let height = visibleRange.upperBound - visibleRange.lowerBound
        let jumpThreshold = 0.03 * height

        var lines: [[PlotPoint]] = []
        var line: [PlotPoint] = []
        func finishLine() {
            if line.count > 1 { lines.append(line) }
            line = []
        }

        var previousX = lower
        var previousY = f(lower)
        if previousY.isFinite { line.append(PlotPoint(x: previousX, y: previousY)) }

        for index in 1...intervals {
            let x = index == intervals ? upper : lower + Double(index) * step
            let y = f(x)

            switch (previousY.isFinite, y.isFinite) {
            case (true, true):
                let bothAbove = previousY > visibleRange.upperBound && y > visibleRange.upperBound
                let bothBelow = previousY < visibleRange.lowerBound && y < visibleRange.lowerBound
                if abs(y - previousY) > jumpThreshold, !bothAbove, !bothBelow,
                   let (left, right) = discontinuity(f, from: previousX, previousY, to: x, y, threshold: jumpThreshold) {
                    line.append(left)
                    finishLine()
                    line = [right]
                }
                line.append(PlotPoint(x: x, y: y))

            case (true, false):
                // Leaving the domain: run right up to its edge.
                let edge = RootFinder.domainEdge(f, finite: previousX, undefined: x)
                let edgeValue = f(edge)
                if edge != previousX, edgeValue.isFinite {
                    line.append(PlotPoint(x: edge, y: edgeValue))
                }
                finishLine()

            case (false, true):
                // Entering the domain: start at its edge.
                let edge = RootFinder.domainEdge(f, finite: x, undefined: previousX)
                let edgeValue = f(edge)
                if edge != x, edgeValue.isFinite {
                    line.append(PlotPoint(x: edge, y: edgeValue))
                }
                line.append(PlotPoint(x: x, y: y))

            case (false, false):
                break
            }
            previousX = x
            previousY = y
        }
        finishLine()
        return lines
    }

    /// If `f` jumps between two samples, the points just either side of the
    /// jump; nil if the change is continuous after all.
    static func discontinuity(
        _ f: (Double) -> Double,
        from x0: Double, _ y0: Double,
        to x1: Double, _ y1: Double,
        threshold: Double
    ) -> (PlotPoint, PlotPoint)? {
        var a = x0, fa = y0
        var b = x1, fb = y1
        for _ in 0..<40 {
            let middle = 0.5 * (a + b)
            if middle <= a || middle >= b { break }
            let value = f(middle)
            guard value.isFinite else {
                return (PlotPoint(x: a, y: fa), PlotPoint(x: b, y: fb))
            }
            // Follow the half that holds most of the change.
            if abs(value - fa) >= abs(fb - value) {
                b = middle
                fb = value
            } else {
                a = middle
                fa = value
            }
            // A continuous curve's change shrinks with the interval, so it
            // soon drops below the threshold; a pole's or a step's never does.
            if abs(fb - fa) <= threshold { return nil }
        }
        guard abs(fb - fa) > threshold else { return nil }
        return (PlotPoint(x: a, y: fa), PlotPoint(x: b, y: fb))
    }
}

/// Tick marks at "nice" values for plot axes.
public enum AxisTicks {
    /// A spacing of 1, 2 or 5 × 10ⁿ that gives about `targetCount` ticks
    /// across `span`.
    public static func step(span: Double, targetCount: Double) -> Double {
        guard span > 0, span.isFinite, targetCount > 0 else { return 1 }
        let raw = span / targetCount
        let magnitude = pow10(Int((log10Value(raw)).rounded(.down)))
        let fraction = raw / magnitude
        let nice: Double
        switch fraction {
        case ..<1.5: nice = 1
        case ..<3: nice = 2
        case ..<7: nice = 5
        default: nice = 10
        }
        return nice * magnitude
    }

    /// The multiples of `step` that fall within `range`.
    public static func values(in range: ClosedRange<Double>, step: Double) -> [Double] {
        guard step > 0, step.isFinite else { return [] }
        // A little slack, so a bound like −0.3 counts as a multiple of 0.1.
        let first = (range.lowerBound / step - 1e-9).rounded(.up)
        let last = (range.upperBound / step + 1e-9).rounded(.down)
        guard first.isFinite, last.isFinite, last >= first, last - first < 10_000 else { return [] }
        return stride(from: first, through: last, by: 1).map { k in
            let value = k * step
            return abs(value) < step * 1e-9 ? 0 : value
        }
    }

    /// How many minor intervals divide one major step: 5 for steps of 1 and
    /// 5, and 4 for steps of 2.
    public static func minorDivisions(for step: Double) -> Int {
        let leading = step / pow10(Int(log10Value(step).rounded(.down)))
        return abs(leading - 2) < 0.01 ? 4 : 5
    }

    /// A label for a tick at `value` on an axis with the given `step`:
    /// `−1.5`, `20`, `2.5e6`, `5e−7`. Every label on an axis gets the same
    /// number of decimals.
    public static func label(_ value: Double, step: Double) -> String {
        if value == 0 { return "0" }
        let magnitude = abs(value)
        let stepExponent = Int((log10Value(step) + 1e-9).rounded(.down))
        var text: String
        if magnitude >= 1e6 || step >= 1e5 || step < 1e-4 {
            // Scientific notation, with just enough mantissa digits for the step.
            let exponent = Int((log10Value(magnitude) + 1e-9).rounded(.down))
            let mantissa = magnitude / pow10(exponent)
            text = formatFixed(mantissa, decimals: max(0, exponent - stepExponent))
            if text.contains(".") {
                while text.hasSuffix("0") { text.removeLast() }
                if text.hasSuffix(".") { text.removeLast() }
            }
            text += "e" + MathPrinter.integer(exponent)
        } else {
            text = formatFixed(magnitude, decimals: max(0, -stepExponent))
        }
        return value < 0 ? "−" + text : text
    }

    // MARK: Helpers

    private static func log10Value(_ value: Double) -> Double {
        Foundation.log10(value)
    }

    private static func pow10(_ exponent: Int) -> Double {
        Foundation.pow(10, Double(exponent))
    }

    private static func formatFixed(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(min(decimals, 12))f", value)
    }
}
