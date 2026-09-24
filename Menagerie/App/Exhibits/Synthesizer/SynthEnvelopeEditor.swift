import SwiftUI
import SynthKit

/// An ADSR envelope drawn as a graph with three draggable handles: the attack peak (time), the
/// decay corner (decay time and sustain level), and the release end (time). Times use log scales
/// so milliseconds and seconds are equally easy to reach. VoiceOver sees four sliders instead.
struct SynthEnvelopeEditor: View {
    @Binding var envelope: SynthPatch.Envelope
    var tint: Color = SynthPalette.accent

    @State private var activeHandle: SynthEnvelopeGeometry.Handle? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let geometry = SynthEnvelopeGeometry(envelope: envelope, size: proxy.size)
                Canvas { context, _ in
                    geometry.draw(in: &context, tint: tint, activeHandle: activeHandle)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if activeHandle == nil {
                                activeHandle = geometry.handle(near: value.startLocation)
                            }
                            if let activeHandle {
                                envelope = geometry.envelope(moving: activeHandle, to: value.location)
                            }
                        }
                        .onEnded { _ in
                            activeHandle = nil
                        }
                )
            }
            .frame(height: 96)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 0) {
                readout("A", SynthFormat.time(envelope.attack))
                readout("D", SynthFormat.time(envelope.decay))
                readout("S", SynthFormat.percent(envelope.sustain))
                readout("R", SynthFormat.time(envelope.release))
            }
            .font(.caption.monospacedDigit())
        }
        .accessibilityRepresentation {
            VStack {
                Slider(value: $envelope.attack, in: SynthPatch.Envelope.attackRange) { Text("Attack") }
                Slider(value: $envelope.decay, in: SynthPatch.Envelope.decayRange) { Text("Decay") }
                Slider(value: $envelope.sustain, in: SynthPatch.Envelope.sustainRange) { Text("Sustain") }
                Slider(value: $envelope.release, in: SynthPatch.Envelope.releaseRange) { Text("Release") }
            }
        }
    }

    private func readout(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(tint).fontWeight(.semibold)
            Text(value).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Maps an envelope to points in the editor and back.
struct SynthEnvelopeGeometry {
    enum Handle {
        case attack, decay, release
    }

    let envelope: SynthPatch.Envelope
    let plot: CGRect

    // Share of the width each segment may use at its longest.
    private static let attackSpan: CGFloat = 0.26
    private static let decaySpan: CGFloat = 0.26
    private static let sustainSpan: CGFloat = 0.14
    private static let releaseSpan: CGFloat = 0.30

    private static let attackScale = LogScale(range: SynthPatch.Envelope.attackRange)
    private static let decayScale = LogScale(range: SynthPatch.Envelope.decayRange)
    private static let releaseScale = LogScale(range: SynthPatch.Envelope.releaseRange)

    init(envelope: SynthPatch.Envelope, size: CGSize) {
        self.envelope = envelope
        plot = CGRect(x: 10, y: 10, width: max(size.width - 20, 1), height: max(size.height - 20, 1))
    }

    var start: CGPoint { CGPoint(x: plot.minX, y: plot.maxY) }

    var attackPoint: CGPoint {
        let fraction = CGFloat(Self.attackScale.position(of: envelope.attack))
        return CGPoint(x: plot.minX + fraction * Self.attackSpan * plot.width, y: plot.minY)
    }

    var decayPoint: CGPoint {
        let fraction = CGFloat(Self.decayScale.position(of: envelope.decay))
        return CGPoint(x: attackPoint.x + fraction * Self.decaySpan * plot.width, y: level(envelope.sustain))
    }

    var sustainEnd: CGPoint {
        CGPoint(x: decayPoint.x + Self.sustainSpan * plot.width, y: decayPoint.y)
    }

    var releasePoint: CGPoint {
        let fraction = CGFloat(Self.releaseScale.position(of: envelope.release))
        return CGPoint(x: sustainEnd.x + fraction * Self.releaseSpan * plot.width, y: plot.maxY)
    }

    private func level(_ value: Double) -> CGFloat {
        plot.maxY - CGFloat(min(max(value, 0), 1)) * plot.height
    }

    /// The handle within reach of `point`, if any.
    func handle(near point: CGPoint) -> Handle? {
        let candidates: [(Handle, CGPoint)] = [(.attack, attackPoint), (.decay, decayPoint), (.release, releasePoint)]
        var best: Handle?
        var bestDistance = CGFloat(34)
        for (handle, position) in candidates {
            let dx = point.x - position.x
            let dy = point.y - position.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < bestDistance {
                best = handle
                bestDistance = distance
            }
        }
        return best
    }

    /// The envelope with `handle` dragged to `point`.
    func envelope(moving handle: Handle, to point: CGPoint) -> SynthPatch.Envelope {
        var result = envelope
        switch handle {
        case .attack:
            let fraction = (point.x - plot.minX) / (Self.attackSpan * plot.width)
            result.attack = Self.attackScale.value(at: Double(fraction))
        case .decay:
            let fraction = (point.x - attackPoint.x) / (Self.decaySpan * plot.width)
            result.decay = Self.decayScale.value(at: Double(fraction))
            result.sustain = min(max(Double((plot.maxY - point.y) / plot.height), 0), 1)
        case .release:
            let fraction = (point.x - sustainEnd.x) / (Self.releaseSpan * plot.width)
            result.release = Self.releaseScale.value(at: Double(fraction))
        }
        return result
    }

    /// The envelope's outline: an RC-style rise, exponential falls, and the sustain plateau.
    func outline() -> Path {
        var path = Path()
        path.move(to: start)
        // The attack chases a target beyond full level (a gentle curve); decay and release chase
        // targets just past theirs (a steep curve), as the engine's envelope does.
        appendCurve(to: &path, from: start, to: attackPoint, steepness: 1.466)
        appendCurve(to: &path, from: attackPoint, to: decayPoint, steepness: 4)
        path.addLine(to: sustainEnd)
        appendCurve(to: &path, from: sustainEnd, to: releasePoint, steepness: 4)
        return path
    }

    /// Adds an exponential approach from `a` to `b`, like an RC circuit: quick at first, then
    /// easing in. Higher steepness front-loads more of the movement.
    private func appendCurve(to path: inout Path, from a: CGPoint, to b: CGPoint, steepness: Double) {
        let steps = 24
        let norm = 1 - exp(-steepness)
        for i in 1 ... steps {
            let u = Double(i) / Double(steps)
            let progress = (1 - exp(-steepness * u)) / norm
            let x = a.x + (b.x - a.x) * CGFloat(u)
            let y = a.y + (b.y - a.y) * CGFloat(progress)
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }

    func draw(in context: inout GraphicsContext, tint: Color, activeHandle: Handle?) {
        // Segment guides.
        var guides = Path()
        for x in [attackPoint.x, decayPoint.x, sustainEnd.x] {
            guides.move(to: CGPoint(x: x, y: plot.minY))
            guides.addLine(to: CGPoint(x: x, y: plot.maxY))
        }
        context.stroke(guides, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        var baseline = Path()
        baseline.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        baseline.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(baseline, with: .color(.secondary.opacity(0.4)), lineWidth: 1)

        // Filled shape and outline.
        let outline = outline()
        var area = outline
        area.addLine(to: CGPoint(x: releasePoint.x, y: plot.maxY))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.4), tint.opacity(0.04)]),
            startPoint: CGPoint(x: 0, y: plot.minY),
            endPoint: CGPoint(x: 0, y: plot.maxY)
        ))
        context.stroke(outline, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Handles.
        for (handle, point) in [(Handle.attack, attackPoint), (.decay, decayPoint), (.release, releasePoint)] {
            let radius: CGFloat = handle == activeHandle ? 7 : 5
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(tint), lineWidth: 2)
        }
    }
}
