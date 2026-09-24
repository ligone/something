import Foundation

/// A cyclic color gradient for coloring escape counts.
///
/// Stops are interpolated in Oklab, a perceptual color space, so gradients
/// stay vivid through their midpoints instead of turning muddy the way
/// straight RGB blends do. The last stop wraps around to the first.
public struct FractalPalette: Identifiable, Sendable {
    public struct Stop: Sendable {
        public var position: Double
        public var red: Double
        public var green: Double
        public var blue: Double

        /// A stop from 8-bit sRGB components.
        public init(_ position: Double, _ red: Int, _ green: Int, _ blue: Int) {
            self.position = position
            self.red = Double(red) / 255
            self.green = Double(green) / 255
            self.blue = Double(blue) / 255
        }
    }

    public let name: String
    public let stops: [Stop]
    /// The color used for points inside the set.
    public let interior: Stop

    public var id: String { name }

    public init(name: String, stops: [Stop], interior: Stop = Stop(0, 0, 0, 0)) {
        precondition(!stops.isEmpty, "A palette needs at least one stop")
        self.name = name
        self.stops = stops.sorted { $0.position < $1.position }
        self.interior = interior
    }

    /// The sRGB color (components in 0...1) at `t`, which wraps around 1.
    ///
    /// Between stops the color follows a Catmull-Rom spline through the
    /// neighboring stops in Oklab, which is smooth across stops (no creases
    /// or plateaus that would show up as bands in the fractal).
    public func color(at t: Double) -> (red: Double, green: Double, blue: Double) {
        let n = stops.count
        guard n > 1 else { return (stops[0].red, stops[0].green, stops[0].blue) }

        var t = t.truncatingRemainder(dividingBy: 1)
        if t < 0 { t += 1 }

        // The segment runs from stop i to stop j, wrapping past the last stop.
        let i: Int
        if let index = stops.lastIndex(where: { $0.position <= t }) {
            i = index
        } else {
            i = n - 1
            t += 1
        }
        let j = (i + 1) % n
        let start = stops[i].position
        var end = stops[j].position
        if j <= i { end += 1 }
        let f = end > start ? (t - start) / (end - start) : 0

        let p0 = Oklab(stops[(i + n - 1) % n])
        let p1 = Oklab(stops[i])
        let p2 = Oklab(stops[j])
        let p3 = Oklab(stops[(i + 2) % n])
        return Oklab.catmullRom(p0, p1, p2, p3, f).sRGB
    }

    /// `count` evenly spaced colors as RGBA8 bytes, ready to upload as a 1D
    /// lookup texture.
    public func rgba8(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: count * 4)
        for i in 0..<count {
            let c = color(at: Double(i) / Double(count))
            bytes[i * 4 + 0] = Self.byte(c.red)
            bytes[i * 4 + 1] = Self.byte(c.green)
            bytes[i * 4 + 2] = Self.byte(c.blue)
        }
        return bytes
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }

}

extension FractalPalette {
    /// The palettes on offer, in display order.
    public static let all: [FractalPalette] = [classic, nebula, aurora, ember, glacier, prism]

    /// The famous Ultra Fractal default: navy, cobalt, white, amber.
    public static let classic = FractalPalette(name: "Classic", stops: [
        Stop(0.0, 0, 7, 100),
        Stop(0.16, 32, 107, 203),
        Stop(0.42, 237, 255, 255),
        Stop(0.6425, 255, 170, 0),
        Stop(0.8575, 0, 2, 0),
    ])

    public static let nebula = FractalPalette(name: "Nebula", stops: [
        Stop(0.0, 20, 6, 48),
        Stop(0.22, 118, 36, 168),
        Stop(0.42, 238, 72, 138),
        Stop(0.6, 255, 170, 96),
        Stop(0.74, 255, 238, 196),
        Stop(0.88, 60, 150, 200),
    ], interior: Stop(0, 8, 4, 18))

    public static let aurora = FractalPalette(name: "Aurora", stops: [
        Stop(0.0, 2, 16, 26),
        Stop(0.25, 20, 140, 110),
        Stop(0.45, 120, 255, 170),
        Stop(0.62, 90, 190, 255),
        Stop(0.8, 150, 80, 220),
    ])

    public static let ember = FractalPalette(name: "Ember", stops: [
        Stop(0.0, 10, 0, 0),
        Stop(0.2, 120, 10, 10),
        Stop(0.42, 235, 90, 20),
        Stop(0.6, 255, 200, 60),
        Stop(0.72, 255, 250, 225),
        Stop(0.86, 90, 20, 30),
    ])

    public static let glacier = FractalPalette(name: "Glacier", stops: [
        Stop(0.0, 4, 12, 40),
        Stop(0.3, 40, 90, 160),
        Stop(0.5, 170, 215, 240),
        Stop(0.62, 255, 255, 255),
        Stop(0.8, 90, 150, 210),
    ], interior: Stop(0, 2, 6, 16))

    public static let prism = FractalPalette(name: "Prism", stops: [
        Stop(0.0, 255, 60, 90),
        Stop(0.17, 255, 170, 40),
        Stop(0.34, 230, 240, 60),
        Stop(0.5, 60, 220, 120),
        Stop(0.67, 40, 180, 255),
        Stop(0.84, 150, 80, 255),
    ])
}

/// Björn Ottosson's Oklab color space.
struct Oklab {
    var l: Double
    var a: Double
    var b: Double

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// Converts from gamma-encoded sRGB components in 0...1.
    init(red: Double, green: Double, blue: Double) {
        let r = Oklab.linear(red)
        let g = Oklab.linear(green)
        let bl = Oklab.linear(blue)
        let lms0 = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl
        let lms1 = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl
        let lms2 = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl
        let l_ = cbrt(lms0)
        let m_ = cbrt(lms1)
        let s_ = cbrt(lms2)
        l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    /// Gamma-encoded sRGB components, clamped to 0...1.
    var sRGB: (red: Double, green: Double, blue: Double) {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let lms0 = l_ * l_ * l_
        let lms1 = m_ * m_ * m_
        let lms2 = s_ * s_ * s_
        let r = 4.0767416621 * lms0 - 3.3077115913 * lms1 + 0.2309699292 * lms2
        let g = -1.2684380046 * lms0 + 2.6097574011 * lms1 - 0.3413193965 * lms2
        let bl = -0.0041960863 * lms0 - 0.7034186147 * lms1 + 1.7076147010 * lms2
        return (Oklab.gamma(r), Oklab.gamma(g), Oklab.gamma(bl))
    }

    init(_ stop: FractalPalette.Stop) {
        self.init(red: stop.red, green: stop.green, blue: stop.blue)
    }

    /// A uniform Catmull-Rom spline through four colors, evaluated between
    /// the middle two.
    static func catmullRom(_ p0: Oklab, _ p1: Oklab, _ p2: Oklab, _ p3: Oklab, _ t: Double) -> Oklab {
        func blend(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            let t2 = t * t
            let t3 = t2 * t
            let linear = (c - a) * t
            let quadratic = (2 * a - 5 * b + 4 * c - d) * t2
            let cubic = (3 * b - a - 3 * c + d) * t3
            return 0.5 * (2 * b + linear + quadratic + cubic)
        }
        return Oklab(
            l: blend(p0.l, p1.l, p2.l, p3.l),
            a: blend(p0.a, p1.a, p2.a, p3.a),
            b: blend(p0.b, p1.b, p2.b, p3.b)
        )
    }

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func gamma(_ c: Double) -> Double {
        let clamped = min(max(c, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}
