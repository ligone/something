import SwiftUI
import SynthKit

/// The stage: a glowing oscilloscope over a log-frequency spectrum analyzer, light rising from
/// the keys being played, and the keyboard along the bottom. A single `TimelineView` drives every
/// layer at display rate from `SynthVisualizerFeed`.
struct SynthStageView: View {
    let model: SynthesizerModel

    var body: some View {
        GeometryReader { proxy in
            let keyboardHeight = min(max(proxy.size.height * 0.19, 104), 160)
            TimelineView(.animation) { timeline in
                let visuals = model.feed.frame(at: timeline.date, localNotes: model.localNotes)
                let base = model.keyboardBaseNote
                VStack(spacing: 10) {
                    Canvas { context, size in
                        let keys = SynthKeyboardLayout(lowestNote: base - 12, octaves: SynthKeyboardView.octaves, size: CGSize(width: size.width, height: keyboardHeight))
                        SynthStageRenderer.draw(visuals, keys: keys, in: &context, size: size)
                    }
                    SynthKeyboardView(model: model, visuals: visuals)
                        .frame(height: keyboardHeight)
                }
                .padding(.top, 58)
                .padding(.bottom, 50)
                .padding(.horizontal, 20)
            }
        }
        .background {
            LinearGradient(colors: [SynthPalette.stageTop, SynthPalette.stageBottom], startPoint: .top, endPoint: .bottom)
        }
        .overlay {
            if let problem = model.audioProblem {
                Label(problem, systemImage: "speaker.slash")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
    }
}

/// Draws the oscilloscope and spectrum analyzer (from `Canvas` renderers on the main thread).
@MainActor
enum SynthStageRenderer {
    private static let labeledFrequencies: [(frequency: Double, label: String)] = [
        (50, "50"), (100, "100"), (200, "200"), (500, "500"), (1_000, "1k"), (2_000, "2k"), (5_000, "5k"), (10_000, "10k"),
    ]

    static func draw(_ visuals: SynthVisualFrame, keys: SynthKeyboardLayout, in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 40, size.height > 40 else { return }
        let scopeCenter = size.height * 0.36
        let scopeAmplitude = size.height * 0.25
        drawBackdrop(visuals, scopeCenter: scopeCenter, scopeAmplitude: scopeAmplitude, in: &context, size: size)
        drawKeyBeams(visuals, keys: keys, in: &context, size: size)
        drawSpectrum(visuals, in: &context, size: size)
        drawScope(visuals, center: scopeCenter, amplitude: scopeAmplitude, in: &context, size: size)
        drawFrequencyScale(in: &context, size: size)
    }

    /// Ambient glow that breathes with the loudness, and a faint graticule.
    private static func drawBackdrop(_ visuals: SynthVisualFrame, scopeCenter: CGFloat, scopeAmplitude: CGFloat, in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let glow = 0.07 + 0.13 * Double(visuals.energy)
        context.fill(Path(bounds), with: .radialGradient(
            Gradient(colors: [SynthPalette.accent.opacity(glow), SynthPalette.accent.opacity(0)]),
            center: CGPoint(x: size.width / 2, y: scopeCenter),
            startRadius: 0,
            endRadius: max(size.width, size.height) * 0.62
        ))

        var grid = Path()
        for column in 1 ..< 10 {
            let x = size.width * CGFloat(column) / 10
            grid.move(to: CGPoint(x: x, y: scopeCenter - scopeAmplitude))
            grid.addLine(to: CGPoint(x: x, y: scopeCenter + scopeAmplitude))
        }
        for level in [-1.0, -0.5, 0.5, 1.0] {
            let y = scopeCenter - scopeAmplitude * CGFloat(level)
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.04)), lineWidth: 1)

        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: scopeCenter))
        axis.addLine(to: CGPoint(x: size.width, y: scopeCenter))
        context.stroke(axis, with: .color(.white.opacity(0.08)), lineWidth: 1)
    }

    /// Columns of light rising from every key that is sounding.
    private static func drawKeyBeams(_ visuals: SynthVisualFrame, keys: SynthKeyboardLayout, in context: inout GraphicsContext, size: CGSize) {
        let height = size.height * 0.45
        for note in keys.notes where note >= 0 && note < visuals.keyGlow.count {
            let glow = Double(visuals.keyGlow[note])
            guard glow > 0.01 else { continue }
            let key = keys.frame(of: note)
            let width = key.width * (SynthKeyboardLayout.isBlack(note) ? 0.9 : 0.62)
            let beam = CGRect(x: key.midX - width / 2, y: size.height - height, width: width, height: height)
            context.fill(Path(roundedRect: beam, cornerRadius: width / 2), with: .linearGradient(
                Gradient(colors: [SynthPalette.accent.opacity(0), SynthPalette.accent.opacity(0.2 * glow)]),
                startPoint: CGPoint(x: beam.midX, y: beam.minY),
                endPoint: CGPoint(x: beam.midX, y: beam.maxY)
            ))
        }
    }

    /// Log-frequency bars, cyan at the bottom through violet to magenta at the top, with a soft
    /// halo and peak-hold caps.
    private static func drawSpectrum(_ visuals: SynthVisualFrame, in context: inout GraphicsContext, size: CGSize) {
        let bands = min(visuals.levels.count, visuals.peaks.count)
        guard bands > 0 else { return }
        let floorY = size.height - 16
        let maxHeight = size.height * 0.5
        let slot = size.width / CGFloat(bands)
        let barWidth = max(slot * 0.64, 1.5)
        let corner = CGSize(width: barWidth / 2, height: barWidth / 2)

        var bars = Path()
        var caps = Path()
        for band in 0 ..< bands {
            let level = CGFloat(min(max(visuals.levels[band], 0), 1))
            let height = max(level * maxHeight, 2)
            let x = CGFloat(band) * slot + (slot - barWidth) / 2
            bars.addRoundedRect(in: CGRect(x: x, y: floorY - height, width: barWidth, height: height), cornerSize: corner)
            let peak = CGFloat(min(max(visuals.peaks[band], 0), 1))
            if peak > 0.03 {
                let y = floorY - max(peak * maxHeight, 2) - 4
                caps.addRoundedRect(in: CGRect(x: x, y: y, width: barWidth, height: 2), cornerSize: CGSize(width: 1, height: 1))
            }
        }

        let shading = GraphicsContext.Shading.linearGradient(
            SynthPalette.spectrum,
            startPoint: CGPoint(x: 0, y: floorY),
            endPoint: CGPoint(x: 0, y: floorY - maxHeight)
        )
        var halo = context
        halo.opacity = 0.22
        halo.stroke(bars, with: shading, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
        var solid = context
        solid.opacity = 0.9
        solid.fill(bars, with: shading)
        context.fill(caps, with: .color(.white.opacity(0.75)))
    }

    /// The oscilloscope trace: four additive strokes from a wide faint halo to a bright core,
    /// fading out at both ends.
    private static func drawScope(_ visuals: SynthVisualFrame, center: CGFloat, amplitude: CGFloat, in context: inout GraphicsContext, size: CGSize) {
        let samples = visuals.scope
        guard samples.count > 1 else { return }
        let pointCount = max(min(samples.count, Int(size.width / 1.5)), 2)
        let gain = CGFloat(visuals.scopeGain)
        let lastIndex = samples.count - 1

        var trace = Path()
        for i in 0 ..< pointCount {
            let t = CGFloat(i) / CGFloat(pointCount - 1)
            let index = min(Int(t * CGFloat(lastIndex)), lastIndex)
            let value = min(max(CGFloat(samples[index]) * gain, -1.15), 1.15)
            let point = CGPoint(x: t * size.width, y: center - value * amplitude)
            if i == 0 { trace.move(to: point) } else { trace.addLine(to: point) }
        }

        var light = context
        light.blendMode = .plusLighter
        light.drawLayer { layer in
            layer.blendMode = .plusLighter
            let strokes: [(width: CGFloat, color: Color)] = [
                (16, SynthPalette.accent.opacity(0.07)),
                (8, SynthPalette.accent.opacity(0.14)),
                (3.2, SynthPalette.accent.opacity(0.45)),
                (1.4, Color(red: 0.86, green: 0.97, blue: 1)),
            ]
            for stroke in strokes {
                layer.stroke(trace, with: .color(stroke.color), style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
            }
            // Let the trace emerge from and dissolve into the dark at the edges.
            layer.blendMode = .destinationOut
            let fade = min(size.width * 0.08, 64)
            layer.fill(Path(CGRect(x: 0, y: 0, width: fade, height: size.height)), with: .linearGradient(
                Gradient(colors: [.black, .black.opacity(0)]),
                startPoint: .zero,
                endPoint: CGPoint(x: fade, y: 0)
            ))
            layer.fill(Path(CGRect(x: size.width - fade, y: 0, width: fade, height: size.height)), with: .linearGradient(
                Gradient(colors: [.black.opacity(0), .black]),
                startPoint: CGPoint(x: size.width - fade, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)
            ))
        }
    }

    private static func drawFrequencyScale(in context: inout GraphicsContext, size: CGSize) {
        let low = SynthVisualizerFeed.minimumFrequency
        let span = log(SynthVisualizerFeed.maximumFrequency / low)
        for mark in labeledFrequencies {
            let x = size.width * CGFloat(log(mark.frequency / low) / span)
            let label = Text(mark.label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.3))
            context.draw(label, at: CGPoint(x: x, y: size.height - 5), anchor: .center)
        }
    }
}
