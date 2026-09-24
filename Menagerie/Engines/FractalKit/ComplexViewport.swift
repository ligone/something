/// A window onto the complex plane.
///
/// `scale` is measured in complex units per *point* on screen, which keeps the
/// viewport independent of display resolution. Screen coordinates have their
/// origin at the top left with y pointing down; the imaginary axis points up.
public struct ComplexViewport: Equatable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var scale: Double

    /// The deepest zoom we allow: double-float arithmetic on the GPU carries
    /// about 48 significant bits, so pixels closer together than this stop
    /// being distinguishable.
    public static let minimumScale = 2e-13
    /// The farthest we let you pull back.
    public static let maximumScale = 0.05

    public init(centerX: Double, centerY: Double, scale: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
    }

    /// The view that frames a whole fractal inside a view of the given size.
    public static func home(for kind: FractalKind, width: Double, height: Double) -> ComplexViewport {
        let w = max(width, 1)
        let h = max(height, 1)
        switch kind {
        case .mandelbrot:
            return ComplexViewport(centerX: -0.74, centerY: 0, scale: max(3.1 / w, 2.5 / h))
        case .julia:
            return ComplexViewport(centerX: 0, centerY: 0, scale: max(3.6 / w, 2.7 / h))
        }
    }

    /// The complex number under a point of the view.
    public func complex(atX x: Double, y: Double, width: Double, height: Double) -> (re: Double, im: Double) {
        (centerX + (x - width / 2) * scale, centerY - (y - height / 2) * scale)
    }

    /// Moves the view so the content follows a drag of `(dx, dy)` points.
    public mutating func pan(dx: Double, dy: Double) {
        centerX -= dx * scale
        centerY += dy * scale
    }

    /// Zooms by `factor` (> 1 zooms in) while keeping the complex number under
    /// `(x, y)` fixed on screen, so zooming follows the pointer.
    public mutating func zoom(by factor: Double, aroundX x: Double, y: Double, width: Double, height: Double) {
        guard factor.isFinite, factor > 0 else { return }
        let anchor = complex(atX: x, y: y, width: width, height: height)
        let newScale = min(max(scale / factor, Self.minimumScale), Self.maximumScale)
        centerX = anchor.re - (x - width / 2) * newScale
        centerY = anchor.im + (y - height / 2) * newScale
        scale = newScale
    }

    /// How many times deeper this view is than `reference`.
    public func magnification(relativeTo reference: ComplexViewport) -> Double {
        reference.scale / scale
    }
}

/// Which fractal to draw.
public enum FractalKind: Equatable, Sendable {
    /// z ← z² + c, starting from z = 0, with c the pixel.
    case mandelbrot
    /// z ← z² + c, starting from z = the pixel, with a fixed c.
    case julia(re: Double, im: Double)

    public var isJulia: Bool {
        if case .julia = self { return true }
        return false
    }
}
