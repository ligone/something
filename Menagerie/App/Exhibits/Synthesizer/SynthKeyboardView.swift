import SwiftUI
import SynthKit

/// Geometry of a piano keyboard spanning whole octaves from a C, in the keyboard's own coordinates.
struct SynthKeyboardLayout {
    let lowestNote: Int
    let highestNote: Int
    let size: CGSize
    let whiteKeyWidth: CGFloat
    let blackKeyWidth: CGFloat
    let blackKeyHeight: CGFloat
    private let frames: [CGRect]

    /// - Parameters:
    ///   - lowestNote: A C.
    ///   - octaves: Whole octaves shown; a final C is added on the right.
    init(lowestNote: Int, octaves: Int, size: CGSize) {
        self.lowestNote = lowestNote
        highestNote = lowestNote + 12 * octaves
        self.size = size
        let whiteCount = 7 * octaves + 1
        whiteKeyWidth = size.width / CGFloat(whiteCount)
        blackKeyWidth = whiteKeyWidth * 0.6
        blackKeyHeight = size.height * 0.62

        var frames: [CGRect] = []
        var whiteIndex = 0
        for note in lowestNote ... highestNote {
            if Self.isBlack(note) {
                // Black keys sit on the boundary to their left white key, nudged the way a real
                // keyboard staggers them within each group.
                let boundary = CGFloat(whiteIndex) * whiteKeyWidth
                let center = boundary + Self.blackOffset(note) * whiteKeyWidth
                frames.append(CGRect(x: center - blackKeyWidth / 2, y: 0, width: blackKeyWidth, height: blackKeyHeight))
            } else {
                frames.append(CGRect(x: CGFloat(whiteIndex) * whiteKeyWidth, y: 0, width: whiteKeyWidth, height: size.height))
                whiteIndex += 1
            }
        }
        self.frames = frames
    }

    var notes: ClosedRange<Int> { lowestNote ... highestNote }

    static func isBlack(_ note: Int) -> Bool {
        switch ((note % 12) + 12) % 12 {
        case 1, 3, 6, 8, 10: return true
        default: return false
        }
    }

    private static func blackOffset(_ note: Int) -> CGFloat {
        switch ((note % 12) + 12) % 12 {
        case 1: return -0.08 // C♯
        case 3: return 0.08 // D♯
        case 6: return -0.1 // F♯
        case 10: return 0.1 // A♯
        default: return 0 // G♯
        }
    }

    /// Frame of a key in keyboard coordinates.
    func frame(of note: Int) -> CGRect {
        guard notes.contains(note) else { return .zero }
        return frames[note - lowestNote]
    }

    /// The key under `point`, with a velocity from how far down the key it was struck (as on a
    /// real piano, playing nearer the front edge is louder).
    func key(at point: CGPoint) -> (note: Int, velocity: Double)? {
        guard point.x >= 0, point.x < size.width, point.y >= 0, point.y <= size.height else { return nil }
        if point.y < blackKeyHeight {
            for note in notes where Self.isBlack(note) && frame(of: note).contains(point) {
                return (note, Self.velocity(point.y / blackKeyHeight))
            }
        }
        for note in notes where !Self.isBlack(note) && frame(of: note).contains(point) {
            return (note, Self.velocity(point.y / size.height))
        }
        return nil
    }

    private static func velocity(_ depth: CGFloat) -> Double {
        0.4 + 0.6 * Double(min(max(depth, 0), 1))
    }
}

/// The on-screen keyboard: three octaves around the computer-keyboard mapping, playable by click
/// and drag (glissando), lighting up for notes from any source.
struct SynthKeyboardView: View {
    let model: SynthesizerModel
    let visuals: SynthVisualFrame

    /// Octaves shown; the computer keyboard's C sits at the start of the second.
    static let octaves = 3

    var body: some View {
        GeometryReader { proxy in
            let base = model.keyboardBaseNote
            let layout = SynthKeyboardLayout(lowestNote: base - 12, octaves: Self.octaves, size: proxy.size)
            Canvas { context, _ in
                Self.draw(layout: layout, visuals: visuals, mappedBase: base, in: &context)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let hit = layout.key(at: value.location)
                        model.pointerMoved(to: hit?.note, velocity: hit?.velocity ?? 0.8)
                    }
                    .onEnded { _ in
                        model.pointerEnded()
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Piano keyboard")
        .accessibilityHint("Click or drag across the keys to play. Keys A to K on your keyboard play too.")
    }

    // MARK: - Drawing

    private static func draw(layout: SynthKeyboardLayout, visuals: SynthVisualFrame, mappedBase: Int, in context: inout GraphicsContext) {
        let accent = SynthPalette.accent
        let labelSize = min(max(layout.whiteKeyWidth * 0.34, 8), 12)

        // White keys.
        for note in layout.notes where !SynthKeyboardLayout.isBlack(note) {
            let rect = layout.frame(of: note).insetBy(dx: 0.75, dy: 0)
            let key = Path(roundedRect: rect, cornerRadius: min(5, rect.width * 0.2), style: .continuous)
            context.fill(key, with: .linearGradient(
                Gradient(colors: [Color(white: 0.96), Color(white: 0.82)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            ))
            let glow = Double(glowLevel(visuals, note))
            if glow > 0.005 {
                context.fill(key, with: .linearGradient(
                    Gradient(colors: [accent.opacity(0.25 * glow), accent.opacity(0.95 * glow)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                ))
            }
            context.stroke(key, with: .color(.black.opacity(0.35)), lineWidth: 0.75)
            drawLabels(note: note, rect: rect, isBlack: false, glow: glow, mappedBase: mappedBase, size: labelSize, in: &context)
        }

        // Black keys on top.
        for note in layout.notes where SynthKeyboardLayout.isBlack(note) {
            let rect = layout.frame(of: note)
            let key = Path(roundedRect: rect, cornerRadius: min(3.5, rect.width * 0.18), style: .continuous)
            context.fill(key, with: .linearGradient(
                Gradient(colors: [Color(white: 0.22), Color(white: 0.05)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            ))
            let glow = Double(glowLevel(visuals, note))
            if glow > 0.005 {
                context.fill(key, with: .linearGradient(
                    Gradient(colors: [accent.opacity(0.3 * glow), accent.opacity(0.9 * glow)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                ))
            }
            // A soft sheen along the front edge.
            let sheen = CGRect(x: rect.minX + 2, y: rect.maxY - 7, width: max(rect.width - 4, 0), height: 3)
            context.fill(Path(roundedRect: sheen, cornerRadius: 1.5), with: .color(.white.opacity(0.14)))
            drawLabels(note: note, rect: rect, isBlack: true, glow: glow, mappedBase: mappedBase, size: labelSize - 1, in: &context)
        }

        // The key bed's shadow across the top.
        let bed = CGRect(x: 0, y: 0, width: layout.size.width, height: 6)
        context.fill(Path(bed), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.55), .black.opacity(0)]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: 6)
        ))
    }

    private static func glowLevel(_ visuals: SynthVisualFrame, _ note: Int) -> Float {
        note >= 0 && note < visuals.keyGlow.count ? visuals.keyGlow[note] : 0
    }

    /// Computer-key letters on the mapped keys, and octave names on the Cs.
    private static func drawLabels(note: Int, rect: CGRect, isBlack: Bool, glow: Double, mappedBase: Int, size: CGFloat, in context: inout GraphicsContext) {
        let offset = note - mappedBase
        let hasLetter = offset >= 0 && offset < SynthKeyMap.labels.count
        let isC = ((note % 12) + 12) % 12 == 0
        var baseline = rect.maxY - size * 0.9

        if isC && !isBlack {
            let name = Text(SynthFormat.noteName(note))
                .font(.system(size: max(size - 2, 7), weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: glow > 0.4 ? 1 : 0.5))
            context.draw(name, at: CGPoint(x: rect.midX, y: baseline), anchor: .center)
            baseline -= size * 1.35
        }
        if hasLetter {
            let color: Color = isBlack ? .white.opacity(0.7) : Color(white: glow > 0.4 ? 1 : 0.32)
            let letter = Text(SynthKeyMap.labels[offset])
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            context.draw(letter, at: CGPoint(x: rect.midX, y: baseline), anchor: .center)
        }
    }
}
