import Foundation

/// A named destination in the Mandelbrot set.
public struct FractalLandmark: Identifiable, Sendable {
    public let name: String
    public let caption: String
    public let centerX: Double
    public let centerY: Double
    /// How much of the complex plane is visible across the view on arrival.
    public let width: Double

    public var id: String { name }

    public init(name: String, caption: String, centerX: Double, centerY: Double, width: Double) {
        self.name = name
        self.caption = caption
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
    }

    public func viewport(viewWidth: Double) -> ComplexViewport {
        ComplexViewport(
            centerX: centerX,
            centerY: centerY,
            scale: max(width / max(viewWidth, 1), ComplexViewport.minimumScale)
        )
    }
}

/// Tools for locating "minibrots", the tiny copies of the whole set that
/// hide along its filaments.
public enum MandelbrotNucleus {
    /// The period of the minibrot whose *atom domain* contains `c`: the step
    /// at which the critical orbit comes closest to zero before escaping.
    /// Newton's method started at `c` with this period converges to that
    /// minibrot's nucleus.
    ///
    /// If the orbit never escapes, `c` is (probably) inside a component, and
    /// the period of the cycle the orbit settles onto is returned instead.
    public static func atomDomainPeriod(re: Double, im: Double, maxIterations: Int) -> Int? {
        var x = 0.0
        var y = 0.0
        var closest = Double.infinity
        var period: Int?
        for n in 1...maxIterations {
            let nextX = x * x - y * y + re
            y = 2 * x * y + im
            x = nextX
            let r2 = x * x + y * y
            if r2 > 4 { return period }
            if r2 < closest {
                closest = r2
                period = n
            }
        }
        return attractingCyclePeriod(re: re, im: im, fromX: x, y: y, maxPeriod: maxIterations)
    }

    /// Continues a settled orbit until it returns to where it was.
    private static func attractingCyclePeriod(re: Double, im: Double, fromX startX: Double, y startY: Double, maxPeriod: Int) -> Int? {
        var x = startX
        var y = startY
        for n in 1...maxPeriod {
            let nextX = x * x - y * y + re
            y = 2 * x * y + im
            x = nextX
            let dx = x - startX
            let dy = y - startY
            if dx * dx + dy * dy < 1e-20 { return n }
        }
        return nil
    }

    /// Solves `f_c^p(0) = 0` for `c` by Newton's method, where the critical
    /// orbit of `c` is periodic with period `p` (the center of a hyperbolic
    /// component). Returns `nil` if the iteration doesn't converge.
    public static func find(nearRe re: Double, im: Double, period: Int, maxSteps: Int = 80) -> (re: Double, im: Double)? {
        guard period > 0 else { return nil }
        var cx = re
        var cy = im
        for _ in 0..<maxSteps {
            // Iterate z ← z² + c together with its derivative dz/dc ← 2·z·dz/dc + 1.
            var zx = 0.0, zy = 0.0
            var dx = 0.0, dy = 0.0
            for _ in 0..<period {
                let ndx = 2 * (zx * dx - zy * dy) + 1
                let ndy = 2 * (zx * dy + zy * dx)
                dx = ndx
                dy = ndy
                let nzx = zx * zx - zy * zy + cx
                zy = 2 * zx * zy + cy
                zx = nzx
            }
            // Newton step: c ← c − z / (dz/dc).
            let denominator = dx * dx + dy * dy
            guard denominator > 0, denominator.isFinite else { return nil }
            let stepX = (zx * dx + zy * dy) / denominator
            let stepY = (zy * dx - zx * dy) / denominator
            cx -= stepX
            cy -= stepY
            guard cx.isFinite, cy.isFinite else { return nil }
            if stepX * stepX + stepY * stepY < 1e-34 { return (cx, cy) }
        }
        return (cx, cy)
    }

    /// Claude Heiland-Allen's estimate of a minibrot's size (roughly the
    /// radius of its cardioid) from its nucleus and period.
    public static func size(re: Double, im: Double, period: Int) -> Double {
        var zx = 0.0, zy = 0.0
        var lx = 1.0, ly = 0.0   // l = ∏ 2·z
        var bx = 1.0, by = 0.0   // b = Σ 1 / l
        guard period > 1 else { return 1 }
        for _ in 1..<period {
            let nzx = zx * zx - zy * zy + re
            zy = 2 * zx * zy + im
            zx = nzx
            let nlx = 2 * (zx * lx - zy * ly)
            let nly = 2 * (zx * ly + zy * lx)
            lx = nlx
            ly = nly
            let l2 = lx * lx + ly * ly
            bx += lx / l2
            by -= ly / l2
        }
        // size = 1 / (b · l²)
        let l2x = lx * lx - ly * ly
        let l2y = 2 * lx * ly
        let px = bx * l2x - by * l2y
        let py = bx * l2y + by * l2x
        return 1 / (px * px + py * py).squareRoot()
    }
}

extension FractalLandmark {
    /// The guided tour, in order. Minibrot coordinates are nuclei located
    /// with `MandelbrotNucleus.find` and checked in the test suite.
    public static let tour: [FractalLandmark] = [
        FractalLandmark(
            name: "Seahorse Valley",
            caption: "Between the main cardioid and the period-2 bulb, filaments curl into seahorse tails, and every tail is trimmed with smaller copies of itself.",
            centerX: -0.7453, centerY: 0.1127, width: 0.012
        ),
        FractalLandmark(
            name: "A Minibrot of Period 78",
            caption: "A complete copy of the whole set, 250,000 times smaller. Newton's method locates its nucleus: the point whose critical orbit returns to zero after exactly 78 steps.",
            centerX: -0.74364417201296329, centerY: 0.13182539739503263, width: 1.2e-5
        ),
        FractalLandmark(
            name: "Elephant Valley",
            caption: "On the eastern cusp of the cardioid, spiraling trunks march in procession toward the boundary.",
            centerX: 0.285, centerY: 0.0115, width: 0.02
        ),
        FractalLandmark(
            name: "The Feigenbaum Point",
            caption: "Along the real axis, bulbs double their period as they shrink toward c ≈ −1.4012. Each bulb is about 4.669 times smaller than the last: Feigenbaum's constant, the same number that marks the onset of chaos everywhere.",
            centerX: -1.401155189092050, centerY: 0, width: 2e-5
        ),
        FractalLandmark(
            name: "Triple Spiral Valley",
            caption: "Three-armed spirals, spirals made of spirals, and at the heart of it all a minibrot of period 151.",
            centerX: -0.088502641834407064, centerY: 0.65450132471807942, width: 8e-7
        ),
        FractalLandmark(
            name: "The Deep End",
            caption: "Three billion times magnification, far beyond what 32-bit floats can resolve. The shader carries every coordinate as the unevaluated sum of two floats.",
            centerX: -0.74358611498050853, centerY: 0.13197000832336828, width: 1.1e-9
        ),
    ]
}
