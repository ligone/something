import SwiftUI

/// Maze Lab's stage colours. The stage is always dark, so these are fixed
/// rather than adapting to the system appearance.
enum MazePalette {
    /// Open floor: near-black navy.
    static let floor = Color(red: 0.035, green: 0.047, blue: 0.094)
    /// Walls: dark slate, a shade lighter at the top of the board, as if lit from above.
    static let wallTop = Color(red: 0.22, green: 0.26, blue: 0.34)
    static let wallBottom = Color(red: 0.15, green: 0.18, blue: 0.25)
    /// The lit top lip of a wall that faces open floor.
    static let wallHighlight = Color(red: 0.37, green: 0.43, blue: 0.55)
    /// The shadowed bottom lip of a wall above open floor.
    static let wallShadow = Color(red: 0.08, green: 0.10, blue: 0.15)
    static let mud = Color(red: 0.36, green: 0.24, blue: 0.14)
    static let mudFleck = Color(red: 0.50, green: 0.35, blue: 0.21)

    /// Freshly carved floor flashes this colour, then fades.
    static let carveGlow = Color(red: 0.55, green: 0.93, blue: 1.0)
    /// Freshly built walls flash this colour.
    static let wallGlow = Color(red: 0.72, green: 0.80, blue: 1.0)
    /// Fresh mud flashes this colour.
    static let mudGlow = Color(red: 1.0, green: 0.72, blue: 0.40)
    /// The generator's working set: the backtracker's stack, Prim's frontier, Wilson's walk.
    static let working = Color(red: 0.74, green: 0.40, blue: 1.0)

    static let start = Color(red: 0.42, green: 0.93, blue: 0.52)
    static let goal = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let path = Color(red: 1.0, green: 0.80, blue: 0.34)
    static let pathCore = Color(red: 1.0, green: 0.97, blue: 0.86)
    /// Cells on a search's frontier, discovered but not yet expanded.
    static let frontier = Color(red: 0.84, green: 0.98, blue: 1.0)
    /// The frontier of the goal-side half of a bidirectional search.
    static let goalFrontier = Color(red: 1.0, green: 0.86, blue: 0.93)
    /// Freshly expanded cells flare this colour before settling into their shade.
    static let flare = Color(red: 0.93, green: 0.99, blue: 1.0)

    /// The shades that `MazeSearchPlayback.shades` indexes: the forward ramp,
    /// then the goal-side ramp, each ``MazeSearchPlayback/shadeCount`` long.
    static let searchShades: [Color] = ramp(forwardStops) + ramp(backwardStops)

    /// The forward ramp as a gradient, for the legend in the controls.
    static let expansionGradient = Gradient(stops: forwardStops.map { stop in
        Gradient.Stop(color: stop.rgb.color, location: CGFloat(stop.location))
    })

    // MARK: Ramps

    private struct RGB {
        var red: Double
        var green: Double
        var blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }

        func mixed(with other: RGB, _ amount: Double) -> RGB {
            RGB(
                red: red + (other.red - red) * amount,
                green: green + (other.green - green) * amount,
                blue: blue + (other.blue - blue) * amount
            )
        }
    }

    private struct Stop {
        var location: Double
        var rgb: RGB
    }

    /// Expansion order, first to last: deep blue, azure, cyan, violet, magenta.
    private static let forwardStops = [
        Stop(location: 0.00, rgb: RGB(red: 0.13, green: 0.20, blue: 0.62)),
        Stop(location: 0.30, rgb: RGB(red: 0.12, green: 0.47, blue: 0.96)),
        Stop(location: 0.55, rgb: RGB(red: 0.16, green: 0.83, blue: 0.94)),
        Stop(location: 0.78, rgb: RGB(red: 0.56, green: 0.47, blue: 0.98)),
        Stop(location: 1.00, rgb: RGB(red: 0.93, green: 0.31, blue: 0.86)),
    ]

    /// The goal side of a bidirectional search: plum, rose, amber.
    private static let backwardStops = [
        Stop(location: 0.00, rgb: RGB(red: 0.42, green: 0.10, blue: 0.36)),
        Stop(location: 0.45, rgb: RGB(red: 0.92, green: 0.33, blue: 0.55)),
        Stop(location: 1.00, rgb: RGB(red: 1.00, green: 0.70, blue: 0.32)),
    ]

    private static let floorRGB = RGB(red: 0.035, green: 0.047, blue: 0.094)

    /// Samples a gradient into ``MazeSearchPlayback/shadeCount`` colours, each
    /// blended a little toward the floor so large explored regions glow
    /// rather than glare.
    private static func ramp(_ stops: [Stop]) -> [Color] {
        let count = MazeSearchPlayback.shadeCount
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            let upper = stops.firstIndex { $0.location >= t } ?? stops.count - 1
            let lower = max(upper - 1, 0)
            let span = stops[upper].location - stops[lower].location
            let amount = span > 0 ? (t - stops[lower].location) / span : 0
            let rgb = stops[lower].rgb.mixed(with: stops[upper].rgb, amount)
            return floorRGB.mixed(with: rgb, 0.9).color
        }
    }
}
