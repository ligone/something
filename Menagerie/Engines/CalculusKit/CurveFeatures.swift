/// The landmarks of a curve in an interval: where it crosses zero, where it
/// peaks and dips, and where its concavity flips.
public struct CurveFeatures: Equatable, Sendable {
    public struct Point: Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public enum ExtremumKind: Hashable, Sendable {
        case minimum, maximum
    }

    /// A local minimum or maximum.
    public struct Extremum: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var kind: ExtremumKind

        public init(x: Double, y: Double, kind: ExtremumKind) {
            self.x = x
            self.y = y
            self.kind = kind
        }
    }

    /// The interval that was searched.
    public var interval: ClosedRange<Double>
    public var roots: [Double]
    public var extrema: [Extremum]
    public var inflectionPoints: [Point]

    public init(interval: ClosedRange<Double>, roots: [Double] = [], extrema: [Extremum] = [], inflectionPoints: [Point] = []) {
        self.interval = interval
        self.roots = roots
        self.extrema = extrema
        self.inflectionPoints = inflectionPoints
    }

    /// Finds the features of `f` in `interval`.
    ///
    /// Roots come from ``RootFinder``. Extrema are sign changes of `f′`: from
    /// + to − is a maximum, from − to + a minimum. That test also catches
    /// corners such as `|x|` at 0 and ignores stationary points that aren't
    /// extrema, such as `x³` at 0. Inflection points are sign changes of `f″`.
    /// A sign change where `f` blows up, as `1/x²` does at 0, is a pole and is
    /// discarded.
    ///
    /// - Parameters:
    ///   - derivative: `f′`, or nil to skip extrema.
    ///   - secondDerivative: `f″`, or nil to skip inflection points.
    ///   - samples: The resolution of the scan.
    ///   - limit: The most features of each kind to report.
    public static func find(
        function f: (Double) -> Double,
        derivative: ((Double) -> Double)?,
        secondDerivative: ((Double) -> Double)?,
        in interval: ClosedRange<Double>,
        samples: Int = 2048,
        limit: Int = 100
    ) -> CurveFeatures {
        let grid = SampleGrid(interval: interval, samples: samples, f: f)
        var features = CurveFeatures(interval: interval)
        features.roots = RootFinder.roots(of: f, derivative: derivative, grid: grid, limit: limit)

        if let derivative {
            let slopes = SampleGrid(xs: grid.xs, ys: grid.xs.map(derivative))
            for change in signChanges(of: derivative, on: slopes, limit: limit) {
                guard let y = continuousValue(of: f, at: change.x, bracket: change.index, grid: grid) else { continue }
                let kind: ExtremumKind = change.before > 0 ? .maximum : .minimum
                features.extrema.append(Extremum(x: change.x, y: y, kind: kind))
            }
        }

        if let secondDerivative {
            let curvature = SampleGrid(xs: grid.xs, ys: grid.xs.map(secondDerivative))
            for change in signChanges(of: secondDerivative, on: curvature, limit: limit) {
                guard let y = continuousValue(of: f, at: change.x, bracket: change.index, grid: grid) else { continue }
                features.inflectionPoints.append(Point(x: change.x, y: y))
            }
        }
        return features
    }

    /// Where `g` changes sign across the grid: the location, the sign before
    /// it, and the grid index of the bracket.
    static func signChanges(
        of g: (Double) -> Double,
        on grid: SampleGrid,
        limit: Int
    ) -> [(x: Double, before: Double, index: Int)] {
        let xs = grid.xs
        let ys = grid.ys
        var changes: [(x: Double, before: Double, index: Int)] = []
        for i in 0..<(xs.count - 1) where changes.count < limit {
            let y0 = ys[i]
            let y1 = ys[i + 1]
            if y0 == 0 || !y0.isFinite {
                // Zero or singular right on a grid point, as f′ is at the cusp
                // of x^(2/3): a sign change if the neighbors differ.
                guard i > 0 else { continue }
                let before = ys[i - 1]
                guard before.isFinite, y1.isFinite, before != 0, y1 != 0, (before < 0) != (y1 < 0) else { continue }
                changes.append((xs[i], before, i))
                continue
            }
            guard y0.isFinite, y1.isFinite, y1 != 0, (y0 < 0) != (y1 < 0) else { continue }
            let x = RootFinder.signChange(g, lower: xs[i], upper: xs[i + 1], tolerance: grid.tolerance)
            changes.append((x, y0, i))
        }

        var merged: [(x: Double, before: Double, index: Int)] = []
        for change in changes {
            if let last = merged.last, change.x - last.x <= grid.mergeDistance { continue }
            merged.append(change)
        }
        return merged
    }

    /// `f(x)`, unless `f` is undefined there or has a pole: a feature found
    /// between grid points `bracket` and `bracket + 1` can't be much larger
    /// than the samples around it.
    static func continuousValue(of f: (Double) -> Double, at x: Double, bracket: Int, grid: SampleGrid) -> Double? {
        var y = f(x)
        if !y.isFinite {
            // A removable singularity, like sin(x)/x at 0, has a finite limit.
            let nudge = max(1e-9 * grid.span, 4 * x.ulp)
            let left = f(x - nudge)
            let right = f(x + nudge)
            guard left.isFinite, right.isFinite,
                  abs(left - right) <= 1e-6 * max(abs(left), abs(right), grid.typicalMagnitude) else { return nil }
            y = 0.5 * (left + right)
        }
        let left = grid.ys[max(0, bracket)]
        let right = grid.ys[min(grid.ys.count - 1, bracket + 1)]
        var neighborhood = grid.typicalMagnitude
        if left.isFinite { neighborhood = max(neighborhood, abs(left)) }
        if right.isFinite { neighborhood = max(neighborhood, abs(right)) }
        return abs(y) <= 1e3 * neighborhood ? y : nil
    }
}
