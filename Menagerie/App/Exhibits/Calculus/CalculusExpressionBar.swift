import CalculusKit
import SwiftUI

/// The function input at the top of the stage: a monospaced field that
/// re-plots as you type, a red underline beneath any offending characters,
/// and chips with curated examples.
///
/// Its height never changes, so an error appearing mid-typing doesn't make
/// the plot below jump: the message takes the chips' place, and the
/// underline is drawn over the field's padding.
struct CalculusExpressionBar: View {
    @Bindable var model: CalculusModel
    @FocusState private var isFocused: Bool

    private static let fieldFont = Font.system(size: 17, weight: .medium, design: .monospaced)
    private let tint = Exhibit.calculus.tint

    init(model: CalculusModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            field
            ZStack(alignment: .leading) {
                if let error = visibleError {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(CalculusPalette.error)
                        .lineLimit(1)
                        .padding(.leading, 4)
                        .transition(.opacity)
                } else {
                    chips
                        .transition(.opacity)
                }
            }
            .frame(height: 28)
        }
        .animation(.easeOut(duration: 0.18), value: visibleError)
    }

    private var visibleError: MathParseError? {
        model.revealsError ? model.parseError : nil
    }

    private var field: some View {
        HStack(spacing: 10) {
            Text("f(x) =")
                .font(Self.fieldFont)
                .foregroundStyle(Color.white.opacity(0.45))
            TextField("", text: $model.source, prompt: Text("Type a function of x, like x·sin(x)"))
                .textFieldStyle(.plain)
                .font(Self.fieldFont)
                .foregroundStyle(Color.white)
                .autocorrectionDisabled()
                .focused($isFocused)
                .onSubmit { model.commitSource() }
                .overlay(alignment: .leading) { errorUnderline }
            statusIcon
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isFocused ? 0.085 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    /// A red bar under the characters the error points at. Invisible text in
    /// the same monospaced font measures out the columns.
    @ViewBuilder
    private var errorUnderline: some View {
        if let error = visibleError {
            let length = model.source.count
            let column = min(error.position, length)
            let width = max(1, min(error.length, length - column))
            HStack(spacing: 0) {
                Text(String(repeating: " ", count: column))
                    .font(Self.fieldFont)
                    .hidden()
                Text(String(repeating: "0", count: width))
                    .font(Self.fieldFont)
                    .hidden()
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(CalculusPalette.error)
                            .frame(height: 2.5)
                            .offset(y: 5)
                    }
            }
            .lineLimit(1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var borderColor: Color {
        if visibleError != nil { return CalculusPalette.error.opacity(0.8) }
        return isFocused ? tint.opacity(0.75) : Color.white.opacity(0.12)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if visibleError != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(CalculusPalette.error)
                .help("This isn't a function yet")
        } else if model.parseError != nil {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Color.white.opacity(0.35))
                .help("Keep typing")
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CalculusPalette.taylor.opacity(0.85))
                .help("Plotted")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(CalculusExample.gallery) { example in
                    ExampleChip(
                        title: example.source,
                        isSelected: model.source == example.source,
                        tint: tint
                    ) {
                        model.choose(example)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

extension CalculusExpressionBar {
    /// A capsule button that loads an example function.
    fileprivate struct ExampleChip: View {
        let title: String
        let isSelected: Bool
        let tint: Color
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(isSelected || isHovering ? 1 : 0.78))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(isSelected ? tint.opacity(0.38) : Color.white.opacity(isHovering ? 0.12 : 0.07))
                    )
                    .overlay(
                        Capsule().strokeBorder(isSelected ? tint.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 0.75)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .help("Plot \(title)")
        }
    }
}
