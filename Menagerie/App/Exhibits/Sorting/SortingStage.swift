import SortKit
import SwiftUI

/// The exhibit's colors. Bars take a rainbow hue from their value; touched
/// bars glow white for comparisons and coral for swaps and writes.
enum SortingPalette {
    /// Hue steps in the rainbow. Bars are grouped by step so that a frame
    /// takes at most this many fills, however many bars there are.
    static let bucketCount = 180

    /// Red through violet.
    static let rainbow: [Color] = (0..<bucketCount).map { bucket in
        let level = Double(bucket) / Double(bucketCount - 1)
        return Color(hue: 0.83 * level, saturation: 0.72, brightness: 1)
    }

    static func bucket(for level: Double) -> Int {
        let scaled = (level * Double(bucketCount - 1)).rounded()
        return min(bucketCount - 1, max(0, Int(scaled)))
    }

    static let compare = Color.white
    static let move = Color(red: 1.0, green: 0.5, blue: 0.3)
    static let read = Color(red: 0.4, green: 0.82, blue: 1.0)
    static let verified = Color(red: 0.3, green: 0.96, blue: 0.5)
    static let mismatch = Color(red: 1.0, green: 0.2, blue: 0.28)
    static let pivot = Color(red: 1.0, green: 0.84, blue: 0.3)

    static func color(for highlight: SortingHighlight) -> Color {
        switch highlight {
        case .compare: compare
        case .move: move
        case .read: read
        case .verified: verified
        case .mismatch: mismatch
        }
    }
}

/// Draws one lane into a `Canvas`: a spotlight on the active range, light
/// beams over recently touched indices, the bars or dots themselves, their
/// highlights, the pivot, the verification sweep and a progress line.
struct SortingRenderer {
    let lane: SortingLane
    let style: SortingStyle
    /// Whether to pin the latest step's highlight at full strength, which is
    /// what you want while paused and stepping.
    let showsLatest: Bool

    /// Glow strengths are quantized into this many levels per highlight kind,
    /// so all the glows of a frame take a handful of fills.
    private static let glowLevels = 6

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let values = lane.values
        guard !values.isEmpty, size.width > 8, size.height > 24 else { return }
        // A strip along the bottom holds the range bracket and progress line.
        let plot = CGRect(x: 0, y: 2, width: size.width, height: size.height - 16)
        let geometry = SortingGeometry(count: values.count, plot: plot, style: style)
        let glows = glowPaths(values: values, geometry: geometry)

        drawFocusRange(geometry: geometry, in: &context)
        drawGuide(geometry: geometry, in: &context)
        fill(glows.beams, opacityScale: 0.13, in: &context)
        drawElements(values: values, geometry: geometry, in: &context)
        fill(glows.overlays, opacityScale: 0.95, in: &context)
        drawPivot(values: values, geometry: geometry, in: &context)
        drawSweepFront(geometry: geometry, in: &context)
        drawProgress(size: size, in: &context)
    }

    // MARK: Elements

    private func drawElements(values: [Int], geometry: SortingGeometry, in context: inout GraphicsContext) {
        var paths = [Path](repeating: Path(), count: SortingPalette.bucketCount)
        var used = [Bool](repeating: false, count: SortingPalette.bucketCount)
        for (index, value) in values.enumerated() {
            let level = lane.level(of: value)
            let bucket = SortingPalette.bucket(for: level)
            geometry.addElement(at: index, level: level, scale: 1, to: &paths[bucket])
            used[bucket] = true
        }
        for bucket in paths.indices where used[bucket] {
            context.fill(paths[bucket], with: .color(SortingPalette.rainbow[bucket]))
        }
    }

    // MARK: Glows

    private struct GlowPaths {
        var beams: [Path]
        var overlays: [Path]
    }

    /// Groups the glowing indices by highlight kind and strength: full-height
    /// beams to go behind the bars, and overlays to go on top of them.
    private func glowPaths(values: [Int], geometry: SortingGeometry) -> GlowPaths {
        let levels = Self.glowLevels
        let slots = SortingHighlight.allCases.count * levels
        var glows = GlowPaths(
            beams: Array(repeating: Path(), count: slots),
            overlays: Array(repeating: Path(), count: slots)
        )

        func add(index: Int, kind: SortingHighlight, strength: Float) {
            let level = min(levels - 1, Int(strength * Float(levels)))
            let slot = Int(kind.rawValue) * levels + level
            glows.beams[slot].addRect(geometry.column(at: index))
            geometry.addElement(at: index, level: lane.level(of: values[index]), scale: 1.9, to: &glows.overlays[slot])
        }

        for index in lane.heat.indices where lane.heat[index] > 0.03 {
            add(index: index, kind: lane.highlight[index], strength: lane.heat[index])
        }
        if showsLatest {
            for touch in lane.latest where values.indices.contains(touch.index) {
                add(index: touch.index, kind: SortingHighlight(touch.kind), strength: 1)
            }
        }
        return glows
    }

    private func fill(_ paths: [Path], opacityScale: Double, in context: inout GraphicsContext) {
        let levels = Self.glowLevels
        for (slot, path) in paths.enumerated() where !path.isEmpty {
            guard let kind = SortingHighlight(rawValue: UInt8(slot / levels)) else { continue }
            let strength = Double(slot % levels + 1) / Double(levels)
            context.fill(path, with: .color(SortingPalette.color(for: kind).opacity(strength * opacityScale)))
        }
    }

    // MARK: Focus

    /// A soft spotlight over the sub-array the algorithm is working on, with a
    /// bracket beneath it.
    private func drawFocusRange(geometry: SortingGeometry, in context: inout GraphicsContext) {
        guard let range = lane.focus.range, !range.isEmpty, range.count < geometry.count else { return }
        let plot = geometry.plot
        let left = geometry.edge(at: range.lowerBound)
        let right = geometry.edge(at: range.upperBound)
        let band = CGRect(x: left, y: plot.minY, width: right - left, height: plot.height)
        context.fill(
            Path(band),
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.075)]),
                startPoint: CGPoint(x: band.midX, y: band.minY),
                endPoint: CGPoint(x: band.midX, y: band.maxY)
            )
        )

        let y = plot.maxY + 5
        var bracket = Path()
        bracket.move(to: CGPoint(x: left + 0.5, y: y - 3))
        bracket.addLine(to: CGPoint(x: left + 0.5, y: y))
        bracket.addLine(to: CGPoint(x: right - 0.5, y: y))
        bracket.addLine(to: CGPoint(x: right - 0.5, y: y - 3))
        context.stroke(bracket, with: .color(.white.opacity(0.4)), lineWidth: 1)
    }

    /// In dot mode, a faint diagonal shows where every dot is headed.
    private func drawGuide(geometry: SortingGeometry, in context: inout GraphicsContext) {
        guard style == .dots else { return }
        var guide = Path()
        guide.move(to: geometry.center(at: 0, level: 0))
        guide.addLine(to: geometry.center(at: geometry.count - 1, level: 1))
        context.stroke(guide, with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
    }

    /// The pivot glows gold, and a dashed line at its height shows the
    /// partition's dividing value: smaller elements go left, larger right.
    private func drawPivot(values: [Int], geometry: SortingGeometry, in context: inout GraphicsContext) {
        guard let pivot = lane.focus.pivot, values.indices.contains(pivot) else { return }
        let level = lane.level(of: values[pivot])
        let y = geometry.top(at: level)
        let range = lane.focus.range ?? 0..<geometry.count
        var line = Path()
        line.move(to: CGPoint(x: geometry.edge(at: range.lowerBound), y: y))
        line.addLine(to: CGPoint(x: geometry.edge(at: range.upperBound), y: y))
        context.stroke(line, with: .color(SortingPalette.pivot.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        var marker = Path()
        geometry.addElement(at: pivot, level: level, scale: 1.9, to: &marker)
        context.fill(marker, with: .color(SortingPalette.pivot))
    }

    // MARK: Sweep and progress

    private func drawSweepFront(geometry: SortingGeometry, in context: inout GraphicsContext) {
        guard lane.phase == .verifying else { return }
        let plot = geometry.plot
        let x = plot.minX + CGFloat(lane.sweep) * geometry.pitch
        let glow = CGRect(x: x - 16, y: plot.minY, width: 32, height: plot.height)
        context.fill(
            Path(glow),
            with: .linearGradient(
                Gradient(colors: [
                    SortingPalette.verified.opacity(0),
                    SortingPalette.verified.opacity(0.4),
                    SortingPalette.verified.opacity(0),
                ]),
                startPoint: CGPoint(x: glow.minX, y: glow.midY),
                endPoint: CGPoint(x: glow.maxX, y: glow.midY)
            )
        )
    }

    private func drawProgress(size: CGSize, in context: inout GraphicsContext) {
        let track = CGRect(x: 0, y: size.height - 3, width: size.width, height: 2)
        context.fill(Path(roundedRect: track, cornerRadius: 1), with: .color(.white.opacity(0.08)))

        let done = lane.phase == .verifying || lane.phase == .sorted
        let fraction = done ? 1 : lane.progress
        guard fraction > 0 else { return }
        var bar = track
        bar.size.width = track.width * CGFloat(fraction)
        let color = done ? SortingPalette.verified : Exhibit.sorting.tint
        context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(color.opacity(0.85)))
    }
}

/// Where each element goes on the canvas.
private struct SortingGeometry {
    let count: Int
    let plot: CGRect
    let style: SortingStyle
    /// Horizontal space per element.
    let pitch: CGFloat
    let barWidth: CGFloat
    let cornerRadius: CGFloat
    let dotRadius: CGFloat

    init(count: Int, plot: CGRect, style: SortingStyle) {
        self.count = count
        self.plot = plot
        self.style = style
        pitch = plot.width / CGFloat(count)
        // Gaps between bars only once there's room for them.
        let gap = pitch >= 3 ? min(pitch * 0.2, 3) : 0
        barWidth = pitch - gap
        cornerRadius = barWidth >= 5 ? min(barWidth * 0.3, 3) : 0
        dotRadius = min(max(pitch * 0.42, 1.4), 5)
    }

    /// The x of the boundary before `index`.
    func edge(at index: Int) -> CGFloat {
        plot.minX + CGFloat(index) * pitch
    }

    /// The full-height column an element occupies.
    func column(at index: Int) -> CGRect {
        CGRect(x: edge(at: index), y: plot.minY, width: pitch, height: plot.height)
    }

    /// The top of a bar, or the center of a dot, for a value level.
    func top(at level: Double) -> CGFloat {
        switch style {
        case .bars:
            plot.maxY - barHeight(at: level)
        case .dots:
            plot.maxY - dotRadius - (plot.height - 2 * dotRadius) * CGFloat(level)
        }
    }

    func center(at index: Int, level: Double) -> CGPoint {
        CGPoint(x: edge(at: index) + pitch / 2, y: top(at: level))
    }

    /// Adds a bar or dot. A `scale` above 1 makes the halo drawn over a
    /// highlighted element: a wider dot, or the bar itself for bars.
    func addElement(at index: Int, level: Double, scale: CGFloat, to path: inout Path) {
        switch style {
        case .bars:
            let height = barHeight(at: level)
            let rect = CGRect(
                x: edge(at: index) + (pitch - barWidth) / 2,
                y: plot.maxY - height,
                width: barWidth,
                height: height
            )
            if cornerRadius > 0 {
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            } else {
                path.addRect(rect)
            }
        case .dots:
            let radius = dotRadius * scale
            let point = center(at: index, level: level)
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    /// Even the smallest value gets a sliver of a bar.
    private func barHeight(at level: Double) -> CGFloat {
        plot.height * CGFloat(0.02 + 0.98 * level)
    }
}

/// A lane drawn on a `Canvas`.
struct SortingLaneCanvas: View {
    let lane: SortingLane
    let style: SortingStyle
    let showsLatest: Bool

    var body: some View {
        Canvas { context, size in
            SortingRenderer(lane: lane, style: style, showsLatest: showsLatest)
                .draw(in: &context, size: size)
        }
        .accessibilityElement()
        .accessibilityLabel("\(lane.algorithm.name), \(lane.values.count) bars")
        .accessibilityValue(accessibilityProgress)
    }

    private var accessibilityProgress: String {
        switch lane.phase {
        case .waiting: "Not started"
        case .sorting: "\(Int(lane.progress * 100)) percent sorted"
        case .verifying, .sorted: "Sorted"
        }
    }
}

/// The whole stage: one big lane, or a two-by-two race.
struct SortingStage: View {
    let model: SortingModel

    var body: some View {
        let lanes = model.lanes
        let showsLatest = !model.isPlaying
        if model.isRacing, lanes.count == 4 {
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    raceLane(lanes[0], showsLatest: showsLatest)
                    raceLane(lanes[1], showsLatest: showsLatest)
                }
                GridRow {
                    raceLane(lanes[2], showsLatest: showsLatest)
                    raceLane(lanes[3], showsLatest: showsLatest)
                }
            }
            .padding(EdgeInsets(top: 58, leading: 20, bottom: 54, trailing: 20))
        } else if let lane = lanes.first {
            SortingLaneCanvas(lane: lane, style: model.style, showsLatest: showsLatest)
                .padding(EdgeInsets(top: 62, leading: 28, bottom: 56, trailing: 28))
        }
    }

    private func raceLane(_ lane: SortingLane, showsLatest: Bool) -> some View {
        SortingRaceLane(lane: lane, place: model.place(of: lane), style: model.style, showsLatest: showsLatest)
    }
}

/// A lane in a race, in a card with its name, step count and finishing place.
private struct SortingRaceLane: View {
    let lane: SortingLane
    let place: Int?
    let style: SortingStyle
    let showsLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lane.algorithm.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("\(lane.counts.steps.formatted()) steps")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 4)
                if let place {
                    SortingPlaceBadge(place: place)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.3), value: place)

            SortingLaneCanvas(lane: lane, style: style, showsLatest: showsLatest)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(place == 1 ? 0.22 : 0.07), lineWidth: 1)
        )
    }
}

/// "1st", "2nd"… in gold, silver and bronze.
private struct SortingPlaceBadge: View {
    let place: Int

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private var title: String {
        switch place {
        case 1: "1ST"
        case 2: "2ND"
        case 3: "3RD"
        default: "\(place)TH"
        }
    }

    private var color: Color {
        switch place {
        case 1: Color(red: 1.0, green: 0.82, blue: 0.3)
        case 2: Color(red: 0.8, green: 0.83, blue: 0.88)
        case 3: Color(red: 0.86, green: 0.58, blue: 0.36)
        default: Color(white: 0.55)
        }
    }
}
