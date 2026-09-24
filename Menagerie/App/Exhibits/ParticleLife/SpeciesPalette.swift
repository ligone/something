import SwiftUI

/// The colors and names of the species.
///
/// Vivid, fairly light hues that glow against the near-black stage. They are
/// ordered so that the first few, which small species counts use, sit far
/// apart on the color wheel.
enum SpeciesPalette {
    private static let entries: [(name: String, red: Double, green: Double, blue: Double)] = [
        ("Coral", 1.00, 0.33, 0.42),
        ("Aqua", 0.25, 0.88, 0.82),
        ("Amber", 1.00, 0.77, 0.25),
        ("Violet", 0.60, 0.45, 1.00),
        ("Lime", 0.50, 0.92, 0.36),
        ("Azure", 0.28, 0.60, 1.00),
        ("Orchid", 1.00, 0.42, 0.80),
        ("Ivory", 0.95, 0.95, 0.90),
    ]

    /// The color of a species.
    static func color(_ species: Int) -> Color {
        let entry = entries[species % entries.count]
        return Color(red: entry.red, green: entry.green, blue: entry.blue)
    }

    /// A short, human-readable name for a species.
    static func name(_ species: Int) -> String {
        entries[species % entries.count].name
    }
}
