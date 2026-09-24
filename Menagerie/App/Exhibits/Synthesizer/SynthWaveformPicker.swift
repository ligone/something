import SwiftUI
import SynthKit

/// A row of buttons, one per waveform, each showing a small drawing of its shape.
struct SynthWaveformPicker: View {
    @Binding var selection: Waveform

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Waveform.allCases) { waveform in
                button(for: waveform)
            }
        }
    }

    private func button(for waveform: Waveform) -> some View {
        let isSelected = waveform == selection
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Button {
            selection = waveform
        } label: {
            SynthWaveformGlyph(waveform: waveform)
                .stroke(isSelected ? Color.white : Color.primary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 12)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? AnyShapeStyle(SynthPalette.accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(waveform.displayName)
        .accessibilityLabel(waveform.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One or two cycles of a waveform, drawn as a line.
struct SynthWaveformGlyph: Shape {
    let waveform: Waveform

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.minY
        let bottom = rect.maxY
        func x(_ t: CGFloat) -> CGFloat { rect.minX + t * rect.width }
        func y(_ level: Double) -> CGFloat { rect.midY - CGFloat(level) * rect.height / 2 }

        switch waveform {
        case .sine:
            for i in 0 ... 32 {
                let t = Double(i) / 32
                let point = CGPoint(x: x(CGFloat(t)), y: y(sin(t * 2 * Double.pi)))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        case .triangle:
            path.move(to: CGPoint(x: x(0), y: rect.midY))
            path.addLine(to: CGPoint(x: x(0.25), y: top))
            path.addLine(to: CGPoint(x: x(0.75), y: bottom))
            path.addLine(to: CGPoint(x: x(1), y: rect.midY))
        case .sawtooth:
            path.move(to: CGPoint(x: x(0), y: bottom))
            path.addLine(to: CGPoint(x: x(0.5), y: top))
            path.addLine(to: CGPoint(x: x(0.5), y: bottom))
            path.addLine(to: CGPoint(x: x(1), y: top))
        case .pulse:
            path.move(to: CGPoint(x: x(0), y: bottom))
            for (start, end) in [(CGFloat(0.12), CGFloat(0.42)), (0.62, 0.92)] {
                path.addLine(to: CGPoint(x: x(start), y: bottom))
                path.addLine(to: CGPoint(x: x(start), y: top))
                path.addLine(to: CGPoint(x: x(end), y: top))
                path.addLine(to: CGPoint(x: x(end), y: bottom))
            }
            path.addLine(to: CGPoint(x: x(1), y: bottom))
        case .supersaw:
            for offset in [CGFloat(-0.07), 0, 0.07] {
                path.move(to: CGPoint(x: x(0.08 + offset), y: bottom))
                path.addLine(to: CGPoint(x: x(0.5 + offset), y: top))
                path.addLine(to: CGPoint(x: x(0.5 + offset), y: bottom))
                path.addLine(to: CGPoint(x: x(0.92 + offset), y: top))
            }
        case .noise:
            let levels: [Double] = [0.1, -0.7, 0.9, -0.2, 0.5, -0.95, 0.3, 0.8, -0.5, 0.15, -0.8, 0.65, -0.3, 0.95, -0.6, 0.2, -0.1]
            for (i, level) in levels.enumerated() {
                let point = CGPoint(x: x(CGFloat(i) / CGFloat(levels.count - 1)), y: y(level))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path
    }
}
