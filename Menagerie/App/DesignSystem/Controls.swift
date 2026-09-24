import SwiftUI

/// A titled group of controls in the control panel.
struct ControlSection<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A compact slider with its title on the left and its current value on the
/// right.
///
///     ParameterSlider("Friction", value: $friction, in: 0...1) { String(format: "%.2f", $0) }
struct ParameterSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride?
    let format: (Value) -> String

    init(
        _ title: String,
        value: Binding<Value>,
        in range: ClosedRange<Value>,
        step: Value.Stride? = nil,
        format: @escaping (Value) -> String = { String(format: "%.2f", Double($0)) }
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 8)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            Group {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .controlSize(.small)
            .labelsHidden()
        }
    }
}

/// A label and value on one line, for read-outs in the control panel.
struct StatRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}

/// A small tinted capsule, used for technology tags.
struct TagChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
    }
}

/// An exhibit's icon: its SF Symbol on a rounded square of its tint.
struct ExhibitGlyph: View {
    let exhibit: Exhibit
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(exhibit.tint.gradient)
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            )
            .overlay(
                Image(systemName: exhibit.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            )
            .frame(width: size, height: size)
            .shadow(color: exhibit.tint.opacity(0.35), radius: size * 0.15, y: size * 0.06)
    }
}

/// Formats large counts compactly: 950, 12.4k, 3.1M.
func compactCount(_ value: Double) -> String {
    switch abs(value) {
    case ..<1_000: String(format: "%.0f", value)
    case ..<1_000_000: String(format: "%.1fk", value / 1_000)
    case ..<1_000_000_000: String(format: "%.1fM", value / 1_000_000)
    default: String(format: "%.1fB", value / 1_000_000_000)
    }
}
