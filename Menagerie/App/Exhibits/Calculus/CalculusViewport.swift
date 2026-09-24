import CoreGraphics
import Foundation

/// Which part of the plane the plot shows, and how to convert between plot
/// coordinates and the view's points (origin top-left, y down).
struct CalculusViewport: Equatable {
    /// The plot coordinates at the middle of the view.
    var centerX: Double
    var centerY: Double
    /// Plot units per point. They differ when y has been stretched.
    var unitsPerPointX: Double
    var unitsPerPointY: Double

    static let scaleLimits: ClosedRange<Double> = 1e-7...1e5

    /// Frames `xRange` across the width; `yRange` down the height, or the
    /// same scale as x (so slopes look true) centered on `centerY`.
    static func framing(
        x xRange: ClosedRange<Double>,
        y yRange: ClosedRange<Double>?,
        centerY: Double = 0,
        in size: CGSize
    ) -> CalculusViewport {
        let width = max(Double(size.width), 1)
        let height = max(Double(size.height), 1)
        let scaleX = (xRange.upperBound - xRange.lowerBound) / width
        let centerX = 0.5 * (xRange.lowerBound + xRange.upperBound)
        if let yRange {
            let scaleY = (yRange.upperBound - yRange.lowerBound) / height
            return CalculusViewport(
                centerX: centerX,
                centerY: 0.5 * (yRange.lowerBound + yRange.upperBound),
                unitsPerPointX: scaleX,
                unitsPerPointY: scaleY
            )
        }
        return CalculusViewport(centerX: centerX, centerY: centerY, unitsPerPointX: scaleX, unitsPerPointY: scaleX)
    }

    // MARK: Ranges

    func xRange(in size: CGSize) -> ClosedRange<Double> {
        let half = 0.5 * Double(size.width) * unitsPerPointX
        return (centerX - half)...(centerX + half)
    }

    func yRange(in size: CGSize) -> ClosedRange<Double> {
        let half = 0.5 * Double(size.height) * unitsPerPointY
        return (centerY - half)...(centerY + half)
    }

    // MARK: Converting

    func screenX(_ x: Double, in size: CGSize) -> CGFloat {
        let offset = (x - centerX) / unitsPerPointX
        return size.width / 2 + CGFloat(offset)
    }

    func screenY(_ y: Double, in size: CGSize) -> CGFloat {
        let offset = (y - centerY) / unitsPerPointY
        return size.height / 2 - CGFloat(offset)
    }

    func plotX(_ screenX: CGFloat, in size: CGSize) -> Double {
        centerX + Double(screenX - size.width / 2) * unitsPerPointX
    }

    func plotY(_ screenY: CGFloat, in size: CGSize) -> Double {
        centerY - Double(screenY - size.height / 2) * unitsPerPointY
    }

    // MARK: Moving

    /// Zooms by `factor` (> 1 zooms in) keeping the point under `anchor` fixed.
    mutating func zoom(by factor: Double, around anchor: CGPoint, in size: CGSize, horizontally: Bool = true, vertically: Bool = true) {
        guard factor.isFinite, factor > 0 else { return }
        let anchorX = plotX(anchor.x, in: size)
        let anchorY = plotY(anchor.y, in: size)
        if horizontally {
            unitsPerPointX = Self.clampScale(unitsPerPointX / factor)
        }
        if vertically {
            unitsPerPointY = Self.clampScale(unitsPerPointY / factor)
        }
        centerX = anchorX - Double(anchor.x - size.width / 2) * unitsPerPointX
        centerY = anchorY + Double(anchor.y - size.height / 2) * unitsPerPointY
    }

    /// This viewport moved by a drag of `translation` points.
    func panned(by translation: CGSize) -> CalculusViewport {
        var moved = self
        moved.centerX -= Double(translation.width) * unitsPerPointX
        moved.centerY += Double(translation.height) * unitsPerPointY
        return moved
    }

    private static func clampScale(_ scale: Double) -> Double {
        min(max(scale, scaleLimits.lowerBound), scaleLimits.upperBound)
    }
}

/// A curated function with a view that frames it well.
struct CalculusExample: Identifiable, Hashable {
    let source: String
    let xRange: ClosedRange<Double>
    /// Nil keeps x and y at the same scale.
    let yRange: ClosedRange<Double>?
    var centerY: Double = 0
    let taylorCenter: Double
    let taylorOrder: Int
    let integralBounds: ClosedRange<Double>

    var id: String { source }

    /// What the exhibit opens with: a curve whose Taylor polynomials hug it
    /// further and further out as the order grows, and whose area from 0 to
    /// π is exactly π.
    static let opening = CalculusExample(
        source: "x·sin(x)",
        xRange: -11...11,
        yRange: nil,
        centerY: 0.6,
        taylorCenter: 0,
        taylorOrder: 6,
        integralBounds: 0...Double.pi
    )

    /// The chips under the input field.
    static let gallery: [CalculusExample] = [
        CalculusExample(source: "sin(x)·x²", xRange: -9...9, yRange: -48...48, taylorCenter: 0, taylorOrder: 7, integralBounds: 0...Double.pi),
        CalculusExample(source: "e^(−x²)", xRange: -3.6...3.6, yRange: -0.75...1.55, taylorCenter: 0, taylorOrder: 6, integralBounds: -1...1),
        CalculusExample(source: "x³ − 3x", xRange: -3.6...3.6, yRange: -4.5...4.5, taylorCenter: 1.5, taylorOrder: 2, integralBounds: -1...1),
        CalculusExample(source: "ln(x)", xRange: -1.5...8.5, yRange: -3.6...3.2, taylorCenter: 1, taylorOrder: 5, integralBounds: 1...2.718281828459045),
        CalculusExample(source: "1/(1+x²)", xRange: -4...4, yRange: -0.8...1.6, taylorCenter: 0, taylorOrder: 8, integralBounds: -1...1),
        CalculusExample(source: "sin(1/x)", xRange: -1.2...1.2, yRange: -1.9...1.9, taylorCenter: 0.6, taylorOrder: 4, integralBounds: 0.2...1),
        CalculusExample(source: "x^x", xRange: -0.6...2.8, yRange: -0.6...3.6, taylorCenter: 1, taylorOrder: 3, integralBounds: 0...1),
        CalculusExample(source: "tanh(x)", xRange: -5...5, yRange: -2.2...2.2, taylorCenter: 0, taylorOrder: 7, integralBounds: -1...2),
    ]

    func viewport(in size: CGSize) -> CalculusViewport {
        CalculusViewport.framing(x: xRange, y: yRange, centerY: centerY, in: size)
    }
}
