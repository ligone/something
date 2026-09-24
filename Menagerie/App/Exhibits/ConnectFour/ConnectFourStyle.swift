import ConnectFourKit
import SwiftUI

/// Colors for the board, the discs and the evaluation chips.
enum ConnectFourPalette {
    struct DiscShades {
        let highlight: Color
        let base: Color
        let shade: Color
    }

    static func shades(for color: ConnectFourDiscColor) -> DiscShades {
        switch color {
        case .red:
            return DiscShades(
                highlight: Color(red: 1.00, green: 0.58, blue: 0.54),
                base: Color(red: 0.91, green: 0.18, blue: 0.22),
                shade: Color(red: 0.50, green: 0.04, blue: 0.08)
            )
        case .yellow:
            return DiscShades(
                highlight: Color(red: 1.00, green: 0.97, blue: 0.66),
                base: Color(red: 0.99, green: 0.79, blue: 0.12),
                shade: Color(red: 0.64, green: 0.40, blue: 0.00)
            )
        }
    }

    /// The flat color of a disc, for glows and small markers.
    static func solid(_ color: ConnectFourDiscColor) -> Color {
        shades(for: color).base
    }

    static let boardLight = Color(red: 0.18, green: 0.42, blue: 0.95)
    static let boardDark = Color(red: 0.06, green: 0.19, blue: 0.62)
    static let boardDeep = Color(red: 0.03, green: 0.11, blue: 0.40)
    static let cavity = Color(red: 0.02, green: 0.04, blue: 0.14)
    static let cavityGlow = Color(red: 0.07, green: 0.12, blue: 0.32)

    static let good = Color(red: 0.24, green: 0.84, blue: 0.47)
    static let bad = Color(red: 0.98, green: 0.36, blue: 0.33)
    static let even = Color(white: 0.62)

    /// Green for moves that are good for the player to move, red for bad
    /// ones, gray for even.
    static func tint(for score: C4Score) -> Color {
        switch score {
        case .win: return good
        case .loss: return bad
        case .draw: return even
        case .estimate(let value): return value > 0 ? good : (value < 0 ? bad : even)
        }
    }
}

/// Drawing code shared by the board layers and the loose discs.
enum ConnectFourArt {
    /// Draws a glossy plastic disc, lit from the upper left, with the raised
    /// ring that real discs have.
    static func drawDisc(
        _ context: GraphicsContext,
        at center: CGPoint,
        radius r: CGFloat,
        color: ConnectFourDiscColor,
        opacity: Double = 1
    ) {
        var context = context
        context.opacity = opacity
        let shades = ConnectFourPalette.shades(for: color)
        let bounds = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
        let disc = Path(ellipseIn: bounds)

        let light = CGPoint(x: center.x - r * 0.35, y: center.y - r * 0.42)
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [shades.highlight, shades.base, shades.shade]),
            center: light,
            startRadius: 0,
            endRadius: r * 1.6
        ))

        let ring = Path(ellipseIn: bounds.insetBy(dx: r * 0.3, dy: r * 0.3))
        context.stroke(ring.offsetBy(dx: 0, dy: r * 0.035), with: .color(Color.white.opacity(0.25)), lineWidth: r * 0.07)
        context.stroke(ring, with: .color(shades.shade.opacity(0.5)), lineWidth: r * 0.07)

        let glint = CGRect(x: center.x - r * 0.64, y: center.y - r * 0.74, width: r * 0.76, height: r * 0.46)
        context.fill(Path(ellipseIn: glint), with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0)]),
            center: CGPoint(x: glint.midX, y: glint.midY),
            startRadius: 0,
            endRadius: r * 0.42
        ))

        context.stroke(disc, with: .color(Color.black.opacity(0.28)), lineWidth: max(1, r * 0.045))
    }
}

/// A single disc as a view, for the hover preview, Claude's thinking
/// indicator and the result banner.
struct ConnectFourDiscView: View {
    let color: ConnectFourDiscColor

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            ConnectFourArt.drawDisc(
                context,
                at: CGPoint(x: size.width / 2, y: size.height / 2),
                radius: radius * 0.97,
                color: color
            )
        }
        .accessibilityHidden(true)
    }
}
