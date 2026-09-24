import ConnectFourKit
import SwiftUI

/// The stage: the board, the discs, the evaluation chips and everything that
/// moves.
///
/// The board is drawn in layers so that only moving parts redraw each frame:
/// the cavity behind the holes, the discs, the blue front panel with its
/// holes cut out, then highlights on top. Discs fall *behind* the front panel
/// and show through the holes as they pass, like the real thing.
struct ConnectFourStage: View {
    let model: ConnectFourModel

    var body: some View {
        GeometryReader { proxy in
            let layout = ConnectFourLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                ConnectFourBoardBack(layout: layout)
                ConnectFourDiscLayer(
                    layout: layout,
                    discs: model.discs,
                    fading: model.fading,
                    isMoving: model.isMoving
                )
                ConnectFourBoardFront(layout: layout)
                ConnectFourHighlightLayer(layout: layout, highlights: highlights)
                chips(in: layout)
                hoverPreview(in: layout)
                hintArrow(in: layout)
                thinkingGhost(in: layout)
                columnTargets(in: layout)
                resultBanner(in: layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Overlays

    /// One chip per column with the engine's score for dropping a disc there.
    private func chips(in layout: ConnectFourLayout) -> some View {
        let analysis = model.showsAnalysis ? model.currentAnalysis : nil
        let best = analysis?.bestColumn
        return ZStack(alignment: .topLeading) {
            if let analysis {
                ForEach(analysis.scoredColumns, id: \.self) { column in
                    if let score = analysis.scores[column] {
                        ConnectFourScoreChip(
                            score: score,
                            isBest: column == best,
                            isHinted: column == model.hintColumn,
                            unit: layout.unit
                        )
                        .frame(width: layout.chipSize.width, height: layout.chipSize.height)
                        .position(x: layout.x(ofColumn: column), y: layout.chipY)
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: analysis?.board.key)
        .allowsHitTesting(false)
    }

    /// Your disc, hovering translucently over the column under the pointer.
    @ViewBuilder
    private func hoverPreview(in layout: ConnectFourLayout) -> some View {
        if let column = model.previewColumn, let human = model.human {
            ConnectFourDiscView(color: model.color(of: human))
                .frame(width: 2 * layout.discRadius, height: 2 * layout.discRadius)
                .opacity(0.55)
                .position(x: layout.x(ofColumn: column), y: layout.laneY)
                .animation(.spring(response: 0.26, dampingFraction: 0.82), value: column)
                .allowsHitTesting(false)
        }
    }

    /// A bobbing arrow over the column the hint recommends.
    @ViewBuilder
    private func hintArrow(in layout: ConnectFourLayout) -> some View {
        if let column = model.hintColumn, model.isHumanTurn, model.previewColumn != column {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: layout.unit * 0.46, weight: .semibold))
                    .foregroundStyle(ConnectFourPalette.good)
                    .shadow(color: ConnectFourPalette.good.opacity(0.7), radius: 10)
                    .offset(y: CGFloat(sin(time * 4)) * layout.unit * 0.06)
            }
            .position(x: layout.x(ofColumn: column), y: layout.laneY)
            .allowsHitTesting(false)
            .accessibilityLabel("Hint: column \(column + 1)")
        }
    }

    /// While Claude thinks, a translucent disc hovers over its current
    /// favorite and drifts as the search changes its mind.
    @ViewBuilder
    private func thinkingGhost(in layout: ConnectFourLayout) -> some View {
        if let column = model.ghostColumn {
            let color = model.color(of: model.game.playerToMove)
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ConnectFourDiscView(color: color)
                    .opacity(0.42 + 0.14 * sin(time * 3.4))
                    .offset(y: CGFloat(sin(time * 2.3)) * layout.unit * 0.06)
            }
            .frame(width: 2 * layout.discRadius, height: 2 * layout.discRadius)
            .position(x: layout.x(ofColumn: column), y: layout.laneY)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: column)
            .allowsHitTesting(false)
        }
    }

    /// Invisible strips over the columns that track the pointer and take
    /// clicks.
    private func columnTargets(in layout: ConnectFourLayout) -> some View {
        ForEach(0..<C4Board.columnCount, id: \.self) { column in
            let target = layout.target(forColumn: column)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: target.width, height: target.height)
                .onHover { inside in
                    model.hover(column, isInside: inside)
                }
                .onTapGesture {
                    model.drop(in: column)
                }
                .accessibilityElement()
                .accessibilityLabel("Column \(column + 1)")
                .accessibilityHint("Drops a disc")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    model.drop(in: column)
                }
                .position(x: target.midX, y: target.midY)
        }
    }

    /// "You win!", "Claude wins" or "Draw", in the band above the board once
    /// the winning line has lit up.
    private func resultBanner(in layout: ConnectFourLayout) -> some View {
        ZStack {
            if model.showsResult, let outcome = model.game.outcome {
                let content = bannerContent(for: outcome)
                ConnectFourResultBanner(
                    title: content.title,
                    subtitle: content.subtitle,
                    color: content.color,
                    actionTitle: model.isDemo ? nil : "Play Again",
                    action: { model.newGame() }
                )
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .position(layout.bannerCenter)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: model.showsResult)
    }

    private func bannerContent(for outcome: C4Outcome) -> (title: String, subtitle: String, color: ConnectFourDiscColor?) {
        let next = model.isDemo ? " · next game shortly" : ""
        guard let winner = outcome.winner else {
            return ("Draw", "The board is full" + next, nil)
        }
        let color = model.color(of: winner)
        let subtitle = "Four in a row on move \(model.game.moves.count)" + next
        guard let human = model.human else {
            return ("\(color.name) wins", subtitle, color)
        }
        return (winner == human ? "You win!" : "Claude wins", subtitle, color)
    }

    // MARK: - Highlights

    private var highlights: ConnectFourHighlights {
        var highlights = ConnectFourHighlights()
        highlights.hoverColumn = model.previewColumn

        if let outcome = model.game.outcome, case .win(let winner, let lines) = outcome {
            let cells = outcome.winningCells
            highlights.winningLines = lines
            highlights.winningCells = Array(cells)
            highlights.winnerColor = model.color(of: winner)
            highlights.revealDate = model.winRevealDate
            highlights.dimmedCells = model.discs.map(\.cell).filter { !cells.contains($0) }
        }

        if let column = model.hintColumn, model.isHumanTurn, let human = model.human {
            let row = model.game.board.height(ofColumn: column)
            if row < C4Board.rowCount {
                highlights.hint = C4Cell(column: column, row: row)
                highlights.hintColor = model.color(of: human)
            }
        }

        if model.showsAnalysis, !model.game.isOver {
            for player in C4Player.allCases {
                for cell in model.game.board.threats(for: player) {
                    highlights.threats.append(ConnectFourThreat(cell: cell, color: model.color(of: player)))
                }
            }
        }
        return highlights
    }
}

// MARK: - Board layers

/// The inside of the board, seen through the holes, and the shadow the
/// board casts on the stage. It only redraws when the stage changes size.
struct ConnectFourBoardBack: View {
    let layout: ConnectFourLayout

    var body: some View {
        let layout = self.layout
        Canvas { context, _ in
            ConnectFourBoardArt.drawBack(context, layout: layout)
        }
        .allowsHitTesting(false)
    }
}

/// The blue front panel with its holes, feet and gloss. It only redraws when
/// the stage changes size.
struct ConnectFourBoardFront: View {
    let layout: ConnectFourLayout

    var body: some View {
        let layout = self.layout
        Canvas { context, _ in
            ConnectFourBoardArt.drawFront(context, layout: layout)
        }
        .allowsHitTesting(false)
    }
}

/// The discs, including any that are falling or fading. It redraws every
/// frame only while something moves.
struct ConnectFourDiscLayer: View {
    let layout: ConnectFourLayout
    let discs: [ConnectFourDisc]
    let fading: [ConnectFourDisc]
    let isMoving: Bool

    var body: some View {
        let layout = self.layout
        let discs = self.discs
        let fading = self.fading
        TimelineView(.animation(minimumInterval: nil, paused: !isMoving)) { timeline in
            Canvas { context, _ in
                ConnectFourBoardArt.drawDiscs(context, layout: layout, discs: discs, fading: fading, date: timeline.date)
            }
        }
        .allowsHitTesting(false)
    }
}

/// What the highlight layer draws over the board.
struct ConnectFourHighlights {
    var hoverColumn: Int?
    var winningLines: [C4Line] = []
    var winningCells: [C4Cell] = []
    var winnerColor: ConnectFourDiscColor?
    var revealDate: Date?
    var dimmedCells: [C4Cell] = []
    var hint: C4Cell?
    var hintColor = ConnectFourDiscColor.red
    var threats: [ConnectFourThreat] = []

    /// Whether anything pulses, so the layer must redraw every frame.
    var isAnimated: Bool {
        winnerColor != nil || hint != nil
    }
}

/// An empty cell where one more disc would make four in a row.
struct ConnectFourThreat {
    var cell: C4Cell
    var color: ConnectFourDiscColor
}

/// Highlights over the board: the column under the pointer, threat markers,
/// the hint and the glowing winning line.
struct ConnectFourHighlightLayer: View {
    let layout: ConnectFourLayout
    let highlights: ConnectFourHighlights

    var body: some View {
        let layout = self.layout
        let highlights = self.highlights
        TimelineView(.animation(minimumInterval: nil, paused: !highlights.isAnimated)) { timeline in
            Canvas { context, _ in
                ConnectFourBoardArt.drawHighlights(context, layout: layout, highlights: highlights, date: timeline.date)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Drawing

/// Canvas drawing for the board layers.
enum ConnectFourBoardArt {
    static func drawBack(_ context: GraphicsContext, layout: ConnectFourLayout) {
        let unit = layout.unit
        let frame = Path(roundedRect: layout.board, cornerRadius: ConnectFourLayout.cornerRadius * unit)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Color.black.opacity(0.6), radius: unit * 0.45, x: 0, y: unit * 0.3))
            layer.fill(frame, with: .color(ConnectFourPalette.cavity))
        }
        for column in 0..<C4Board.columnCount {
            for row in 0..<C4Board.rowCount {
                let hole = layout.holeRect(column: column, row: row)
                context.fill(Path(ellipseIn: hole), with: .radialGradient(
                    Gradient(colors: [ConnectFourPalette.cavityGlow, ConnectFourPalette.cavity]),
                    center: CGPoint(x: hole.midX, y: hole.midY + hole.height * 0.2),
                    startRadius: 0,
                    endRadius: hole.width * 0.6
                ))
            }
        }
    }

    static func drawFront(_ context: GraphicsContext, layout: ConnectFourLayout) {
        let unit = layout.unit
        let board = layout.board
        let corner = ConnectFourLayout.cornerRadius * unit
        let top = CGPoint(x: board.midX, y: board.minY)
        let bottom = CGPoint(x: board.midX, y: board.maxY)

        drawFeet(context, layout: layout)

        var panel = Path(roundedRect: board, cornerRadius: corner)
        for column in 0..<C4Board.columnCount {
            for row in 0..<C4Board.rowCount {
                panel.addEllipse(in: layout.holeRect(column: column, row: row))
            }
        }
        let evenOdd = FillStyle(eoFill: true)

        // The panel's own shadow falls into every hole, which gives each one
        // a soft inner shadow along its upper edge.
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Color.black.opacity(0.65), radius: unit * 0.07, x: 0, y: unit * 0.05))
            layer.fill(
                panel,
                with: .linearGradient(
                    Gradient(colors: [ConnectFourPalette.boardLight, ConnectFourPalette.boardDark]),
                    startPoint: top,
                    endPoint: bottom
                ),
                style: evenOdd
            )
        }

        // Gloss across the upper half.
        context.fill(
            panel,
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)]),
                startPoint: top,
                endPoint: CGPoint(x: board.midX, y: board.minY + board.height * 0.5)
            ),
            style: evenOdd
        )

        // Bevelled rims: the upper inside edge in shadow, the lower one lit.
        let rimWidth = max(1, unit * 0.03)
        for column in 0..<C4Board.columnCount {
            for row in 0..<C4Board.rowCount {
                let hole = layout.holeRect(column: column, row: row)
                context.stroke(
                    Path(ellipseIn: hole),
                    with: .linearGradient(
                        Gradient(colors: [Color.black.opacity(0.4), Color.white.opacity(0.28)]),
                        startPoint: CGPoint(x: hole.midX, y: hole.minY),
                        endPoint: CGPoint(x: hole.midX, y: hole.maxY)
                    ),
                    lineWidth: rimWidth
                )
            }
        }

        // A bright edge along the top of the frame.
        context.stroke(
            Path(roundedRect: board.insetBy(dx: 0.75, dy: 0.75), cornerRadius: corner),
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)]),
                startPoint: top,
                endPoint: bottom
            ),
            lineWidth: 1.5
        )
    }

    /// Two splayed feet under the board's lower corners.
    private static func drawFeet(_ context: GraphicsContext, layout: ConnectFourLayout) {
        let unit = layout.unit
        let board = layout.board
        let top = board.maxY - unit * 0.5
        let bottom = board.maxY + unit * ConnectFourLayout.footHeight
        let sides: [CGFloat] = [-1, 1]
        for side in sides {
            let anchor = side < 0 ? board.minX + unit * 0.6 : board.maxX - unit * 0.6
            let shadow = CGRect(x: anchor - unit * 0.6, y: bottom - unit * 0.06, width: unit * 1.2, height: unit * 0.14)
            context.fill(Path(ellipseIn: shadow), with: .color(Color.black.opacity(0.4)))

            var foot = Path()
            foot.move(to: CGPoint(x: anchor - side * unit * 0.25, y: top))
            foot.addLine(to: CGPoint(x: anchor + side * unit * 0.25, y: top))
            foot.addLine(to: CGPoint(x: anchor + side * unit * 0.47, y: bottom))
            foot.addLine(to: CGPoint(x: anchor - side * unit * 0.3, y: bottom))
            foot.closeSubpath()
            context.fill(foot, with: .linearGradient(
                Gradient(colors: [ConnectFourPalette.boardDark, ConnectFourPalette.boardDeep]),
                startPoint: CGPoint(x: anchor, y: top),
                endPoint: CGPoint(x: anchor, y: bottom)
            ))
        }
    }

    static func drawDiscs(
        _ context: GraphicsContext,
        layout: ConnectFourLayout,
        discs: [ConnectFourDisc],
        fading: [ConnectFourDisc],
        date: Date
    ) {
        let radius = layout.discRadius
        for disc in discs {
            let lift = ConnectFourPhysics.height(after: date.timeIntervalSince(disc.start), row: disc.cell.row)
            var center = layout.center(of: disc.cell)
            center.y -= CGFloat(lift) * layout.unit
            ConnectFourArt.drawDisc(context, at: center, radius: radius, color: disc.color)
        }

        for disc in fading {
            let progress = min(1, max(0, date.timeIntervalSince(disc.start) / ConnectFourPhysics.vanishDuration))
            guard progress < 1 else { continue }
            ConnectFourArt.drawDisc(
                context,
                at: layout.center(of: disc.cell),
                radius: radius * CGFloat(1 - 0.3 * progress),
                color: disc.color,
                opacity: 1 - progress
            )
        }

        // A small dot marks the most recent disc once it has landed.
        if let last = discs.last,
           date.timeIntervalSince(last.start) >= ConnectFourPhysics.duration(toRow: last.cell.row) {
            let center = layout.center(of: last.cell)
            let dot = radius * 0.14
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: 2 * dot, height: 2 * dot)),
                with: .color(Color.white.opacity(0.7))
            )
        }
    }

    static func drawHighlights(
        _ context: GraphicsContext,
        layout: ConnectFourLayout,
        highlights: ConnectFourHighlights,
        date: Date
    ) {
        let unit = layout.unit

        // The column under the pointer brightens a little.
        if let column = highlights.hoverColumn {
            let band = CGRect(
                x: layout.x(ofColumn: column) - unit * 0.47,
                y: layout.board.minY + unit * 0.12,
                width: unit * 0.94,
                height: layout.board.height - unit * 0.24
            )
            context.fill(Path(roundedRect: band, cornerRadius: unit * 0.3), with: .color(Color.white.opacity(0.07)))
        }

        // Threats: dashed rings in empty cells that would complete a four,
        // small for red and large for yellow so both show when they share one.
        let dash: [CGFloat] = [unit * 0.06, unit * 0.045]
        for threat in highlights.threats {
            let center = layout.center(of: threat.cell)
            let radius = unit * (threat.color == .red ? 0.12 : 0.19)
            let ring = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
            context.stroke(
                Path(ellipseIn: ring),
                with: .color(ConnectFourPalette.solid(threat.color).opacity(0.9)),
                style: StrokeStyle(lineWidth: max(1.5, unit * 0.035), dash: dash)
            )
        }

        // The hint: a ghost of your disc where it would land, ringed in green.
        if let hint = highlights.hint {
            let pulse = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 5)
            let center = layout.center(of: hint)
            ConnectFourArt.drawDisc(
                context,
                at: center,
                radius: layout.discRadius,
                color: highlights.hintColor,
                opacity: 0.25 + 0.15 * pulse
            )
            let radius = layout.holeRadius
            let ring = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
            context.stroke(
                Path(ellipseIn: ring),
                with: .color(ConnectFourPalette.good.opacity(0.55 + 0.45 * pulse)),
                lineWidth: max(2, unit * 0.05)
            )
        }

        // The win: every other disc dims, then a glowing line sweeps through
        // the winning four and their rims pulse.
        guard let color = highlights.winnerColor, let reveal = highlights.revealDate else { return }
        let elapsed = date.timeIntervalSince(reveal)
        let dimming = min(1, max(0, elapsed / 0.3))
        for cell in highlights.dimmedCells {
            context.fill(
                Path(ellipseIn: layout.holeRect(column: cell.column, row: cell.row)),
                with: .color(Color.black.opacity(0.45 * dimming))
            )
        }
        guard elapsed > 0 else { return }

        let progress = min(1, elapsed / 0.45)
        let pulse = 0.8 + 0.2 * sin(elapsed * 4.5)
        let sweep = CGFloat(progress)
        let glow = ConnectFourPalette.solid(color)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: glow, radius: unit * 0.22))
            for cell in highlights.winningCells {
                let center = layout.center(of: cell)
                let radius = layout.discRadius + unit * 0.025
                let ring = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
                layer.stroke(
                    Path(ellipseIn: ring),
                    with: .color(Color.white.opacity(0.95 * pulse * progress)),
                    lineWidth: max(2, unit * 0.05)
                )
            }
            for line in highlights.winningLines {
                let start = layout.center(of: line.start)
                let end = layout.center(of: line.end)
                var path = Path()
                path.move(to: start)
                path.addLine(to: CGPoint(
                    x: start.x + (end.x - start.x) * sweep,
                    y: start.y + (end.y - start.y) * sweep
                ))
                layer.stroke(
                    path,
                    with: .color(Color.white.opacity(0.9)),
                    style: StrokeStyle(lineWidth: unit * 0.09, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Chips and banner

/// The engine's score for one column: green when dropping a disc there is
/// good for the player to move, red when it is bad, brighter the stronger.
struct ConnectFourScoreChip: View {
    let score: C4Score
    let isBest: Bool
    let isHinted: Bool
    let unit: CGFloat

    var body: some View {
        let magnitude = abs(score.normalized)
        let tint = ConnectFourPalette.tint(for: score)
        let corner = unit * 0.11
        let outline = isHinted ? ConnectFourPalette.good : Color.white
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(tint.opacity(0.14 + 0.5 * magnitude))
            Capsule()
                .fill(tint)
                .frame(width: max(unit * 0.08, unit * 0.68 * CGFloat(magnitude)), height: max(2, unit * 0.035))
                .padding(.bottom, unit * 0.05)
            Text(ConnectFourFormat.label(for: score))
                .font(.system(size: max(9, unit * 0.155), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .padding(.horizontal, unit * 0.05)
                .padding(.bottom, unit * 0.05)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(outline.opacity(isBest || isHinted ? 0.85 : 0.12), lineWidth: isBest || isHinted ? 1.5 : 1)
        }
        .animation(.snappy(duration: 0.25), value: score)
    }
}

/// The result of a finished game.
struct ConnectFourResultBanner: View {
    let title: String
    let subtitle: String
    let color: ConnectFourDiscColor?
    let actionTitle: String?
    let action: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let color {
                ConnectFourDiscView(color: color)
                    .frame(width: 34, height: 34)
            } else {
                Image(systemName: "equal.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            if let actionTitle {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .tint(Exhibit.connectFour.tint)
                .controlSize(.large)
                .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }
}
