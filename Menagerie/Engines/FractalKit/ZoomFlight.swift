import Foundation

/// A smooth camera flight between two viewports, following van Wijk and
/// Nuij's "Smooth and efficient zooming and panning" (2003).
///
/// Panning at a fixed zoom feels slow when you're deep in, so the optimal
/// path pulls back while it travels and dives in again as it arrives. It
/// treats the view as a point `(x, y)` plus a visible width `w` and moves at
/// constant perceived speed, which is what makes ten-billion-fold zooms
/// read as one continuous motion.
public struct ZoomFlight: Sendable {
    public let start: ComplexViewport
    public let end: ComplexViewport
    /// The on-screen width, in points, that the viewports are measured against.
    public let viewWidth: Double
    /// A natural duration in seconds for this flight.
    public let duration: Double

    private let rho: Double
    private let pathLength: Double
    private let isPureZoom: Bool
    private let r0: Double
    private let dx: Double
    private let dy: Double
    private let distance: Double
    private let w0: Double
    private let w1: Double

    /// - Parameters:
    ///   - rho: The trade-off between zooming and panning; √2 is the value
    ///     the paper found most pleasing.
    ///   - speed: Path units per second.
    public init(
        from start: ComplexViewport,
        to end: ComplexViewport,
        viewWidth: Double,
        rho: Double = 2.0.squareRoot(),
        speed: Double = 1.3
    ) {
        self.start = start
        self.end = end
        self.viewWidth = viewWidth
        self.rho = rho
        w0 = start.scale * viewWidth
        w1 = end.scale * viewWidth
        dx = end.centerX - start.centerX
        dy = end.centerY - start.centerY
        distance = (dx * dx + dy * dy).squareRoot()

        let rho2 = rho * rho
        isPureZoom = distance < 1e-9 * min(w0, w1)
        if isPureZoom {
            // No travel: the width changes exponentially.
            r0 = 0
            pathLength = abs(log(w1 / w0)) / rho
        } else {
            let b0 = (w1 * w1 - w0 * w0 + rho2 * rho2 * distance * distance) / (2 * w0 * rho2 * distance)
            let b1 = (w1 * w1 - w0 * w0 - rho2 * rho2 * distance * distance) / (2 * w1 * rho2 * distance)
            // The paper's r(b) = ln(√(b² + 1) − b), written as −asinh(b) so it
            // stays accurate for the huge |b| that deep zooms produce.
            r0 = -asinh(b0)
            let r1 = -asinh(b1)
            pathLength = (r1 - r0) / rho
        }
        duration = max(pathLength / speed, 0.4)
    }

    /// The viewport at `progress` ∈ 0...1 along the path.
    public func viewport(at progress: Double) -> ComplexViewport {
        let t = min(max(progress, 0), 1)
        if t == 0 { return start }
        if t == 1 { return end }

        let u: Double
        let width: Double
        if isPureZoom {
            u = t
            width = w0 * exp(log(w1 / w0) * t)
        } else {
            let s = t * pathLength
            let coshR0 = cosh(r0)
            u = w0 / (rho * rho * distance) * (coshR0 * tanh(rho * s + r0) - sinh(r0))
            width = w0 * coshR0 / cosh(rho * s + r0)
        }
        return ComplexViewport(
            centerX: start.centerX + u * dx,
            centerY: start.centerY + u * dy,
            scale: width / viewWidth
        )
    }
}
