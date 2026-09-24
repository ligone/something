/// A rectangle whose opposite edges are glued together: a flat torus.
///
/// A particle leaving through the right edge re-enters on the left, and two
/// particles near opposite edges are close neighbors. Distances use the
/// minimum-image convention, so they are measured along the shortest way round.
public struct TorusDomain: Hashable, Sendable {
    /// The extent along x, in world units.
    public let width: Float
    /// The extent along y, in world units.
    public let height: Float

    /// Creates a domain of the given size. Both sides must be positive.
    public init(width: Float, height: Float) {
        precondition(width > 0 && height > 0, "A TorusDomain needs a positive width and height")
        self.width = width
        self.height = height
    }

    /// Creates a domain with the given shape (width ÷ height) and area.
    ///
    /// Keeping the area fixed while the shape follows the window keeps the
    /// particle density, and therefore the look of the dynamics, unchanged.
    public init(aspectRatio: Float, area: Float) {
        let shape = min(max(aspectRatio, 0.05), 20)
        self.init(width: (area * shape).squareRoot(), height: (area / shape).squareRoot())
    }

    /// Width ÷ height.
    public var aspectRatio: Float { width / height }

    /// Width × height.
    public var area: Float { width * height }

    /// Maps any coordinate into `0 ..< period`.
    ///
    /// Values already in range are returned unchanged, which keeps the common
    /// case cheap. Non-finite input maps to 0, so a corrupt value can never
    /// escape the domain.
    @inline(__always)
    public static func wrap(_ value: Float, period: Float) -> Float {
        if value >= 0 && value < period { return value }
        var wrapped = value - period * (value / period).rounded(.down)
        // Rounding can land exactly on `period`, e.g. for a tiny negative input.
        if wrapped >= period { wrapped -= period }
        if !(wrapped >= 0) { wrapped = 0 }
        return wrapped
    }

    /// Maps a point into the domain.
    public func wrapped(x: Float, y: Float) -> (x: Float, y: Float) {
        (Self.wrap(x, period: width), Self.wrap(y, period: height))
    }

    /// Whether a point lies in `[0, width) × [0, height)`.
    public func contains(x: Float, y: Float) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
    }

    /// The shortest displacement that leads from the first point to the second.
    public func displacement(fromX x0: Float, y y0: Float, toX x1: Float, y y1: Float) -> (dx: Float, dy: Float) {
        (Self.shortest(x1 - x0, period: width), Self.shortest(y1 - y0, period: height))
    }

    /// The distance between two points, measured the shortest way round.
    public func distance(fromX x0: Float, y y0: Float, toX x1: Float, y y1: Float) -> Float {
        let (dx, dy) = displacement(fromX: x0, y: y0, toX: x1, y: y1)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Folds a coordinate difference into `-period/2 ... period/2`.
    @inline(__always)
    static func shortest(_ delta: Float, period: Float) -> Float {
        delta - period * (delta / period).rounded()
    }
}
