import SwiftUI
import SynthKit

/// The filter's frequency response, computed from the same transfer function the voices use.
/// It doubles as an XY pad: drag left and right for cutoff, up and down for resonance.
struct SynthFilterResponseView: View {
    @Binding var filter: SynthPatch.Filter
    /// Sample rate to evaluate the digital response at (0 while audio is off).
    var sampleRate: Double

    private static let lowestDecibels = -42.0
    private static let highestDecibels = 26.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = Double(min(max(value.location.x / max(size.width, 1), 0), 1))
                        let y = Double(min(max(value.location.y / max(size.height, 1), 0), 1))
                        filter.cutoff = LogScale.cutoff.value(at: x)
                        filter.resonance = 1 - y
                    }
            )
        }
        .frame(height: 84)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Drag sideways for cutoff, up and down for resonance")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filter response")
        .accessibilityValue("\(SynthFormat.frequency(filter.cutoff)), resonance \(SynthFormat.percent(filter.resonance))")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 4, size.height > 4 else { return }
        let rate = sampleRate > 0 ? sampleRate : 48_000
        let tint = SynthPalette.accent

        func y(forDecibels decibels: Double) -> CGFloat {
            let t = (decibels - Self.lowestDecibels) / (Self.highestDecibels - Self.lowestDecibels)
            return size.height * CGFloat(1 - min(max(t, 0), 1))
        }

        // Decade lines and the 0 dB reference.
        var grid = Path()
        for frequency in [100.0, 1_000.0, 10_000.0] {
            let x = size.width * CGFloat(LogScale.cutoff.position(of: frequency))
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        let unity = y(forDecibels: 0)
        grid.move(to: CGPoint(x: 0, y: unity))
        grid.addLine(to: CGPoint(x: size.width, y: unity))
        context.stroke(grid, with: .color(Color.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

        // The response curve.
        let steps = max(Int(size.width / 3), 24)
        var curve = Path()
        for i in 0 ... steps {
            let position = Double(i) / Double(steps)
            let frequency = LogScale.cutoff.value(at: position)
            let magnitude = SVFilter.magnitude(at: frequency, cutoff: filter.cutoff, resonance: filter.resonance, mode: filter.mode, sampleRate: rate)
            let point = CGPoint(x: size.width * CGFloat(position), y: y(forDecibels: 20 * log10(max(magnitude, 1e-6))))
            if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
        }
        var area = curve
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.35), tint.opacity(0.03)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        context.stroke(curve, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Cutoff marker.
        let cutoffX = size.width * CGFloat(LogScale.cutoff.position(of: filter.cutoff))
        let peak = SVFilter.magnitude(at: filter.cutoff, cutoff: filter.cutoff, resonance: filter.resonance, mode: filter.mode, sampleRate: rate)
        let cutoffY = y(forDecibels: 20 * log10(max(peak, 1e-6)))
        let dot = Path(ellipseIn: CGRect(x: cutoffX - 4.5, y: cutoffY - 4.5, width: 9, height: 9))
        context.fill(dot, with: .color(.white))
        context.stroke(dot, with: .color(tint), lineWidth: 2)

        let label = Text(SynthFormat.frequency(filter.cutoff))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.secondary)
        let labelX = min(max(cutoffX, 30), size.width - 30)
        context.draw(label, at: CGPoint(x: labelX, y: 9), anchor: .center)
    }
}
