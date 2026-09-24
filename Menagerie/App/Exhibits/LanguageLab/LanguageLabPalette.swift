import SwiftUI

extension LanguageLab {
    /// The stage's colors.
    ///
    /// Categorical colors come in a fixed order whose neighbors stay
    /// distinguishable under protanopia and deuteranopia on the dark stage.
    /// Colored words use lighter tints of the same hues, which keep at least
    /// 5.7:1 contrast against a card. Sentiment runs red to green through a
    /// neutral gray, always paired with a signed number or bar direction. The
    /// heatmap uses one hue that brightens with similarity.
    enum Palette {
        static let accent = Exhibit.languageLab.tint
        static let ink = Color.white.opacity(0.88)
        static let secondaryInk = Color.white.opacity(0.62)
        static let mutedInk = Color.white.opacity(0.48)
        static let hairline = Color.white.opacity(0.08)
        static let track = Color.white.opacity(0.07)
        static let cardFill = Color.white.opacity(0.045)
        /// Roughly the card surface, for rings that separate overlapping marks.
        static let surface = Color(white: 0.11)

        // MARK: Categories

        private static let categoricalHues: [RGB] = [
            RGB(0x3987E5), RGB(0xD95926), RGB(0x199E70), RGB(0xC98500),
            RGB(0xD55181), RGB(0x008300), RGB(0x9085E9), RGB(0xE66767),
        ]

        /// The categorical color in slot `index`; gray past the eighth.
        static func categorical(_ index: Int) -> Color {
            categoricalHues.indices.contains(index) ? categoricalHues[index].color : Color(white: 0.52)
        }

        /// A lighter tint of slot `index` for coloring text.
        static func categoricalText(_ index: Int) -> Color {
            categoricalHues.indices.contains(index) ? categoricalHues[index].mixed(with: .white, 0.3).color : Color(white: 0.7)
        }

        static func entity(_ kind: EntityKind) -> Color {
            categorical(EntityKind.allCases.firstIndex(of: kind) ?? 0)
        }

        /// Marks (bars, swatches) for a part of speech. Function words recede
        /// to gray so the content words stand out.
        static func partOfSpeech(_ partOfSpeech: PartOfSpeech) -> Color {
            switch partOfSpeech {
            case .function: Color(white: 0.42)
            case .other: categorical(6)
            default: categorical(PartOfSpeech.allCases.firstIndex(of: partOfSpeech) ?? 0)
            }
        }

        /// Text color for a word with this part of speech.
        static func partOfSpeechText(_ partOfSpeech: PartOfSpeech?) -> Color {
            switch partOfSpeech {
            case nil, .function?: Color.white.opacity(0.5)
            case .other?: categoricalText(6)
            case let partOfSpeech?: categoricalText(PartOfSpeech.allCases.firstIndex(of: partOfSpeech) ?? 0)
            }
        }

        // MARK: Sentiment

        private static let negativeHue = RGB(0xE66767)
        private static let neutralHue = RGB(0x4A4A47)
        private static let positiveHue = RGB(0x26A88A)

        static let negative = negativeHue.color
        static let neutral = neutralHue.color
        static let positive = positiveHue.color

        /// Red for −1, gray for 0, green for +1.
        static func sentiment(_ score: Double) -> Color {
            let clamped = min(max(score, -1), 1)
            return clamped < 0
                ? neutralHue.mixed(with: negativeHue, -clamped).color
                : neutralHue.mixed(with: positiveHue, clamped).color
        }

        // MARK: Similarity

        private static let heatStops: [RGB] = [
            RGB(0x2B1824), RGB(0x5E1F45), RGB(0xA0306F), RGB(0xE04D93), RGB(0xFF8DC0), RGB(0xFFD3E6),
        ]

        /// Dark for 0, bright for 1.
        static func heat(_ value: Double) -> Color {
            let position = min(max(value, 0), 1) * Double(heatStops.count - 1)
            let lower = min(Int(position), heatStops.count - 2)
            return heatStops[lower].mixed(with: heatStops[lower + 1], position - Double(lower)).color
        }

        static var heatGradient: Gradient {
            Gradient(colors: heatStops.map(\.color))
        }

        // MARK: Difficulty

        /// Status colors, reserved for the difficulty of sentences.
        static let hard = RGB(0xFAB219).color
        static let veryHard = RGB(0xEC6A5A).color
        /// Underlines words of three or more syllables.
        static let longWord = categoricalText(6)

        static func difficulty(ofGrade grade: Double) -> Color? {
            if grade >= 14 { return veryHard }
            if grade >= 10 { return hard }
            return nil
        }

        /// sRGB components, so colors can be blended.
        struct RGB {
            let red: Double
            let green: Double
            let blue: Double

            static let white = RGB(0xFFFFFF)

            init(_ hex: UInt32) {
                red = Double((hex >> 16) & 0xFF) / 255
                green = Double((hex >> 8) & 0xFF) / 255
                blue = Double(hex & 0xFF) / 255
            }

            init(red: Double, green: Double, blue: Double) {
                self.red = red
                self.green = green
                self.blue = blue
            }

            var color: Color {
                Color(red: red, green: green, blue: blue)
            }

            func mixed(with other: RGB, _ amount: Double) -> RGB {
                RGB(
                    red: red + (other.red - red) * amount,
                    green: green + (other.green - green) * amount,
                    blue: blue + (other.blue - blue) * amount
                )
            }
        }
    }

    /// Number formats used across the exhibit.
    enum Format {
        /// "+0.42", "−0.18" (with a true minus sign), or "0.00".
        static func signed(_ value: Double, digits: Int = 2) -> String {
            let text = String(format: "%.\(digits)f", abs(value))
            guard Double(text) != 0 else { return text }
            return (value > 0 ? "+" : "\u{2212}") + text
        }

        static func decimal(_ value: Double, digits: Int = 1) -> String {
            String(format: "%.\(digits)f", value)
        }

        /// "97.3%", or "<0.1%" for tiny shares.
        static func percent(_ value: Double) -> String {
            if value > 0 && value < 0.001 { return "<0.1%" }
            return String(format: "%.1f%%", value * 100)
        }

        /// A US school grade. The formulas go below zero for very simple
        /// text, which reads better as zero.
        static func grade(_ value: Double) -> String {
            String(format: "%.1f", max(0, value))
        }

        static func duration(_ seconds: Double) -> String {
            let total = Int(seconds.rounded())
            if total < 60 { return "\(total) s" }
            return "\(total / 60) min \(total % 60) s"
        }
    }

    /// Display names for BCP 47 language codes.
    enum LanguageNames {
        /// The language's name in the user's own language: "French".
        static func name(_ code: String) -> String {
            Locale.current.localizedString(forIdentifier: code) ?? code
        }

        /// The language's name for itself: "français", "日本語".
        static func nativeName(_ code: String) -> String? {
            Locale(identifier: code).localizedString(forIdentifier: code)
        }
    }
}
