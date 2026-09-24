import ProseKit
import SwiftUI

extension LanguageLab {
    // MARK: - Language

    struct LanguageCard: View {
        let model: Model
        let analysis: Analysis

        var body: some View {
            StageCard("Language", symbol: "globe", source: "NLLanguageRecognizer") {
                if let top = analysis.language.hypotheses.first {
                    VStack(alignment: .leading, spacing: 14) {
                        header(top)
                        VStack(spacing: 7) {
                            ForEach(analysis.language.hypotheses.prefix(5)) { guess in
                                HypothesisRow(guess: guess, isTop: guess.code == top.code)
                            }
                        }
                        if analysis.sentenceLanguages.count > 1 {
                            SentenceLanguageStrip(model: model, analysis: analysis)
                        }
                    }
                } else {
                    ChartCaption("Not enough text to identify a language.")
                }
            }
        }

        private func header(_ top: LanguageGuess) -> some View {
            let name = LanguageNames.name(top.code)
            let native = LanguageNames.nativeName(top.code)
            let subtitle = native.map { $0 == name ? top.code : "\($0) \u{00B7} \(top.code)" } ?? top.code
            return HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Format.percent(top.probability))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.white)
                    Text("confidence")
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                }
            }
        }
    }

    private struct HypothesisRow: View {
        let guess: LanguageGuess
        let isTop: Bool

        var body: some View {
            HStack(spacing: 10) {
                Text(LanguageNames.name(guess.code))
                    .font(.callout)
                    .foregroundStyle(isTop ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
                    .frame(width: 112, alignment: .leading)
                ValueBar(fraction: guess.probability, color: isTop ? Palette.accent : Color.white.opacity(0.3), height: 8)
                Text(Format.percent(guess.probability))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 50, alignment: .trailing)
            }
            .help("\(guess.code): \(Format.percent(guess.probability))")
        }
    }

    /// One segment per sentence, as wide as the sentence is long, colored by
    /// the language found in it.
    private struct SentenceLanguageStrip: View {
        let model: Model
        let analysis: Analysis
        @State private var hovered: Int?

        var body: some View {
            let languages = analysis.sentenceLanguages
            VStack(alignment: .leading, spacing: 8) {
                Text("\(languages.count) LANGUAGES, SENTENCE BY SENTENCE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.mutedInk)

                GeometryReader { proxy in
                    let gap: CGFloat = 2
                    let count = analysis.sentences.count
                    let weights = analysis.sentences.map { Double(max($0.span.count, 10)) }
                    let total = max(weights.reduce(0, +), 1)
                    let usable = max(proxy.size.width - gap * CGFloat(max(count - 1, 0)), 0)
                    HStack(spacing: gap) {
                        ForEach(analysis.sentences) { sentence in
                            let slot = sentence.languageCode.flatMap { languages.firstIndex(of: $0) }
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(slot.map { Palette.categorical($0) } ?? Color.white.opacity(0.2))
                                .opacity(hovered == nil || hovered == sentence.id ? 1 : 0.4)
                                .frame(width: usable * CGFloat(weights[sentence.id] / total))
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside {
                                        hovered = sentence.id
                                    } else if hovered == sentence.id {
                                        hovered = nil
                                    }
                                    model.hover(inside, spans: [sentence.span], from: "language:\(sentence.id)")
                                }
                        }
                    }
                }
                .frame(height: 16)

                readout
                    .font(.caption)
                    .lineLimit(1)
                    .frame(height: 15, alignment: .leading)

                FlowLayout(spacing: 10, lineSpacing: 5) {
                    ForEach(Array(languages.enumerated()), id: \.element) { slot, code in
                        HStack(spacing: 5) {
                            Swatch(color: Palette.categorical(slot))
                            Text(LanguageNames.name(code))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        .font(.caption)
                    }
                }
            }
        }

        @ViewBuilder
        private var readout: some View {
            if let hovered, analysis.sentences.indices.contains(hovered) {
                let sentence = analysis.sentences[hovered]
                let name = LanguageNames.name(sentence.languageCode ?? "und")
                Text("Sentence \(hovered + 1) \u{00B7} \(name) \u{00B7} \(Format.percent(sentence.languageConfidence))")
                    .foregroundStyle(Palette.ink)
            } else {
                Text("Hover a segment to find its sentence.")
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }

    // MARK: - Sentiment

    struct SentimentCard: View {
        let model: Model
        let analysis: Analysis
        @State private var hovered: Int?

        var body: some View {
            StageCard("Sentiment", symbol: "theatermasks", source: "NLTagger") {
                let scored = analysis.sentences.filter { $0.sentiment != nil }
                if scored.isEmpty {
                    ChartCaption("NaturalLanguage has no sentiment model for this text’s language.")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 18) {
                            SentimentGauge(score: analysis.overallSentiment ?? 0)
                                .frame(width: 150, height: 100)
                            extremes(of: scored)
                        }
                        SentimentBars(sentences: analysis.sentences, hovered: hovered) { index in
                            hovered = index
                            if let index {
                                model.highlightSentences([index], from: "sentiment")
                            } else {
                                model.clearHighlight(from: "sentiment")
                            }
                        }
                        .frame(height: 118)
                        readout
                            .frame(height: 34, alignment: .topLeading)
                    }
                }
            }
        }

        private func extremes(of scored: [SentenceReading]) -> some View {
            let warmest = scored.max { ($0.sentiment ?? 0) < ($1.sentiment ?? 0) }
            let coldest = scored.min { ($0.sentiment ?? 0) < ($1.sentiment ?? 0) }
            return VStack(alignment: .leading, spacing: 10) {
                if let warmest, let score = warmest.sentiment, score > 0 {
                    ExtremeRow(label: "Warmest", sentence: warmest, score: score, model: model)
                }
                if let coldest, let score = coldest.sentiment, score < 0 {
                    ExtremeRow(label: "Coldest", sentence: coldest, score: score, model: model)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        private var readout: some View {
            if let hovered, analysis.sentences.indices.contains(hovered) {
                let sentence = analysis.sentences[hovered]
                let score = sentence.sentiment.map { Format.signed($0) } ?? "no score"
                (Text("\(hovered + 1)  ").foregroundStyle(Palette.mutedInk)
                    + Text(score).foregroundStyle(Palette.ink).bold()
                    + Text("  \(sentence.text)").foregroundStyle(Palette.secondaryInk))
                    .font(.caption)
                    .lineLimit(2)
            } else {
                ChartCaption("One bar per sentence, rising for positive and falling for negative. Hover to find it in the text.")
            }
        }
    }

    private struct ExtremeRow: View {
        let label: String
        let sentence: SentenceReading
        let score: Double
        let model: Model

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.mutedInk)
                    Text(Format.signed(score))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.sentiment(score))
                }
                Text(sentence.text)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                model.hover(inside, spans: [sentence.span], from: "extreme:\(label)")
            }
        }
    }

    /// A semicircular dial from −1 (left) to +1 (right). The colored arc grows
    /// from the neutral top toward the score.
    struct SentimentGauge: View {
        let score: Double

        var body: some View {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Text(Format.signed(score))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(Self.label(for: score))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.bottom, 12)
            }
        }

        private func draw(in context: inout GraphicsContext, size: CGSize) {
            let lineWidth: CGFloat = 10
            let center = CGPoint(x: size.width / 2, y: size.height - 18)
            let radius = min(size.width / 2, center.y) - lineWidth / 2 - 4

            func point(at angle: Double) -> CGPoint {
                CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y - radius * CGFloat(sin(angle)))
            }
            func arc(from start: Double, to end: Double) -> Path {
                var path = Path()
                let steps = max(2, Int(abs(end - start) / (Double.pi / 90)))
                path.move(to: point(at: start))
                for step in 1...steps {
                    path.addLine(to: point(at: start + (end - start) * Double(step) / Double(steps)))
                }
                return path
            }

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(arc(from: .pi, to: 0), with: .color(Palette.track), style: stroke)

            // The score's angle: π at −1, π/2 at 0, 0 at +1.
            let clamped = min(max(score, -1), 1)
            let angle = Double.pi / 2 * (1 - clamped)
            if abs(clamped) > 0.01 {
                context.stroke(arc(from: .pi / 2, to: angle), with: .color(Palette.sentiment(clamped)), style: stroke)
            }

            // A tick at neutral, and the ends labeled.
            var tick = Path()
            tick.move(to: CGPoint(x: center.x, y: center.y - radius - lineWidth / 2 - 3))
            tick.addLine(to: CGPoint(x: center.x, y: center.y - radius + lineWidth / 2 + 3))
            context.stroke(tick, with: .color(Palette.surface), lineWidth: 2)
            let endLabels: [(String, Double)] = [("\u{2212}1", Double.pi), ("+1", 0)]
            for (text, end) in endLabels {
                let position = point(at: end)
                context.draw(
                    Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.mutedInk),
                    at: CGPoint(x: position.x, y: position.y + lineWidth / 2 + 1),
                    anchor: .top
                )
            }

            // The knob, ringed in the surface color so it reads on the arc.
            let knob = point(at: angle)
            context.fill(Path(ellipseIn: CGRect(x: knob.x - 9, y: knob.y - 9, width: 18, height: 18)), with: .color(Palette.surface))
            context.fill(Path(ellipseIn: CGRect(x: knob.x - 7, y: knob.y - 7, width: 14, height: 14)), with: .color(Palette.sentiment(clamped)))
        }

        static func label(for score: Double) -> String {
            if score >= 0.5 { return "Very positive" }
            if score >= 0.15 { return "Positive" }
            if score > -0.15 { return "Neutral" }
            if score > -0.5 { return "Negative" }
            return "Very negative"
        }
    }

    /// A diverging bar chart: one bar per sentence, up for positive scores
    /// and down for negative ones, colored red to green.
    struct SentimentBars: View {
        let sentences: [SentenceReading]
        let hovered: Int?
        let onHover: (Int?) -> Void

        var body: some View {
            GeometryReader { proxy in
                let count = max(sentences.count, 1)
                let showsNumbers = count <= 30
                let plotHeight = proxy.size.height - (showsNumbers ? 16 : 0)
                let slot = proxy.size.width / CGFloat(count)
                let barWidth = min(24, max(2, slot - 3))
                let middle = plotHeight / 2
                let reach = middle - 2

                ZStack(alignment: .topLeading) {
                    gridline(width: proxy.size.width, y: 0.5, color: Palette.hairline)
                    gridline(width: proxy.size.width, y: plotHeight - 0.5, color: Palette.hairline)
                    gridline(width: proxy.size.width, y: middle, color: Color.white.opacity(0.22))

                    ForEach(sentences) { sentence in
                        let x = slot * (CGFloat(sentence.id) + 0.5)
                        let isDimmed = hovered != nil && hovered != sentence.id
                        if let score = sentence.sentiment {
                            let height = max(2, CGFloat(abs(score)) * reach)
                            SentimentBar(score: score, width: barWidth, height: height)
                                .opacity(isDimmed ? 0.35 : 1)
                                .position(x: x, y: score >= 0 ? middle - height / 2 : middle + height / 2)
                        } else {
                            Circle()
                                .strokeBorder(Palette.mutedInk, lineWidth: 1)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: middle)
                        }
                        if showsNumbers {
                            Text("\(sentence.id + 1)")
                                .font(.system(size: 9, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(hovered == sentence.id ? Palette.ink : Palette.mutedInk)
                                .position(x: x, y: plotHeight + 9)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let index = min(sentences.count - 1, max(0, Int(location.x / slot)))
                        if index != hovered {
                            onHover(index)
                        }
                    case .ended:
                        onHover(nil)
                    }
                }
            }
        }

        private func gridline(width: CGFloat, y: CGFloat, color: Color) -> some View {
            Rectangle()
                .fill(color)
                .frame(width: width, height: 1)
                .position(x: width / 2, y: y)
        }
    }

    /// A bar rounded at its value end and square at the baseline.
    private struct SentimentBar: View {
        let score: Double
        let width: CGFloat
        let height: CGFloat

        var body: some View {
            let radius = min(4, width / 2, height)
            let up = score >= 0
            UnevenRoundedRectangle(
                topLeadingRadius: up ? radius : 0,
                bottomLeadingRadius: up ? 0 : radius,
                bottomTrailingRadius: up ? 0 : radius,
                topTrailingRadius: up ? radius : 0,
                style: .continuous
            )
            .fill(Palette.sentiment(score))
            .frame(width: width, height: height)
        }
    }

    // MARK: - Similarity

    struct SimilarityCard: View {
        @Bindable var model: Model
        let analysis: Analysis
        @State private var hovered: CellPosition?

        private static let semanticNote = "Cosine similarity of NLEmbedding sentence vectors: sentences that mean similar things glow, even with no words in common."
        private static let lexicalNote = "Cosine similarity of ProseKit’s TF–IDF word vectors: only shared words count, and rare words count more."

        var body: some View {
            StageCard("Similarity", symbol: "square.grid.3x3.fill") {
                Picker("Compare", selection: $model.similarityKind) {
                    ForEach(SimilarityKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            } content: {
                if analysis.sentences.count < 2 {
                    ChartCaption("Needs at least two sentences.")
                } else {
                    switch model.similarityKind {
                    case .lexical:
                        chart(analysis.lexicalSimilarity, note: Self.lexicalNote)
                    case .semantic:
                        switch model.semanticSimilarity {
                        case .ready(let matrix) where matrix.size == comparedCount:
                            chart(matrix, note: Self.semanticNote, isStale: model.isSemanticSimilarityStale)
                        case .unavailable(let reason):
                            chart(analysis.lexicalSimilarity, note: reason, isStale: model.isSemanticSimilarityStale)
                        default:
                            chart(nil, note: Self.semanticNote)
                        }
                    }
                }
            }
        }

        /// How many sentences the heatmap compares.
        private var comparedCount: Int {
            min(analysis.sentences.count, EmbeddingStore.sentenceLimit)
        }

        /// The heatmap with its readout and legend underneath. With no matrix
        /// yet, a spinner holds the heatmap's place so nothing around it
        /// moves. A stale matrix, from before the latest edit, stays up but
        /// dimmed.
        private func chart(_ matrix: SimilarityMatrix?, note: String, isStale: Bool = false) -> some View {
            let side = SimilarityHeatmap.side(forCount: comparedCount)
            return VStack(alignment: .leading, spacing: 12) {
                Group {
                    if let matrix {
                        SimilarityHeatmap(matrix: matrix, hovered: hovered) { cell in
                            hover(cell)
                        }
                        .opacity(isStale ? 0.5 : 1)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: side, height: side)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 12) {
                    if let matrix {
                        readout(matrix)
                        Spacer(minLength: 8)
                        legend(matrix)
                    }
                }
                .frame(height: 58, alignment: .topLeading)

                ChartCaption(analysis.sentences.count > EmbeddingStore.sentenceLimit
                    ? note + " Showing the first \(EmbeddingStore.sentenceLimit) sentences."
                    : note)
            }
        }

        private func hover(_ cell: CellPosition?) {
            hovered = cell
            if let cell {
                model.highlightSentences([cell.row, cell.column], from: "similarity")
            } else {
                model.clearHighlight(from: "similarity")
            }
        }

        private func legend(_ matrix: SimilarityMatrix) -> some View {
            let range = SimilarityHeatmap.range(of: matrix, count: min(matrix.size, EmbeddingStore.sentenceLimit)) ?? 0...1
            return VStack(alignment: .leading, spacing: 4) {
                Capsule()
                    .fill(LinearGradient(gradient: Palette.heatGradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: 96, height: 6)
                HStack {
                    Text(Format.decimal(range.lowerBound, digits: 2))
                    Spacer()
                    Text(Format.decimal(range.upperBound, digits: 2))
                }
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.mutedInk)
                .frame(width: 96)
            }
        }

        /// The hovered pair, or else the most similar one. Both states have
        /// the same three lines, so hovering never changes the card's height.
        @ViewBuilder
        private func readout(_ matrix: SimilarityMatrix) -> some View {
            if let pair = readoutPair(matrix) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pair.isHovered ? "COMPARING" : "MOST ALIKE")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Palette.mutedInk)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(Format.decimal(pair.similarity, digits: 2))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text("sentences \(min(pair.first, pair.second) + 1) and \(max(pair.first, pair.second) + 1)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.ink)
                    }
                    Text(pair.isHovered ? "Both are lit in the text." : "Hover a cell to compare.")
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                        .lineLimit(1)
                }
            }
        }

        private func readoutPair(_ matrix: SimilarityMatrix) -> (first: Int, second: Int, similarity: Double, isHovered: Bool)? {
            let size = min(matrix.size, EmbeddingStore.sentenceLimit)
            if let hovered, hovered.row < size, hovered.column < size {
                return (hovered.row, hovered.column, matrix[hovered.row, hovered.column], true)
            }
            return matrix.mostSimilarPair(amongFirst: size).map { ($0.first, $0.second, $0.similarity, false) }
        }
    }

    struct CellPosition: Equatable {
        let row: Int
        let column: Int
    }

    /// Every sentence against every other, brighter where they are more
    /// alike. Colors stretch across this text's range of scores; the
    /// diagonal, each sentence against itself, stays gray.
    struct SimilarityHeatmap: View {
        let matrix: SimilarityMatrix
        let hovered: CellPosition?
        let onHover: (CellPosition?) -> Void

        /// Room for the sentence numbers along the top and left.
        static let gutter: CGFloat = 18

        static func cell(forCount count: Int) -> CGFloat {
            min(26, max(6, 250 / CGFloat(max(count, 1))))
        }

        static func side(forCount count: Int) -> CGFloat {
            cell(forCount: count) * CGFloat(count) + gutter
        }

        /// The lowest and highest scores between different sentences among
        /// the first `count`, which the colors stretch across.
        static func range(of matrix: SimilarityMatrix, count: Int) -> ClosedRange<Double>? {
            var lowest = Double.infinity
            var highest = -Double.infinity
            for row in 0..<count {
                for column in 0..<count where row != column {
                    lowest = min(lowest, matrix[row, column])
                    highest = max(highest, matrix[row, column])
                }
            }
            return lowest <= highest ? lowest...highest : nil
        }

        var body: some View {
            let count = min(matrix.size, EmbeddingStore.sentenceLimit)
            let cell = Self.cell(forCount: count)
            let side = Self.side(forCount: count)

            Canvas { context, _ in
                draw(in: &context, count: count, cell: cell)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let column = Int((location.x - Self.gutter) / cell)
                    let row = Int((location.y - Self.gutter) / cell)
                    let inside = location.x >= Self.gutter && location.y >= Self.gutter
                        && row < count && column < count && row != column
                    let position = inside ? CellPosition(row: row, column: column) : nil
                    if position != hovered {
                        onHover(position)
                    }
                case .ended:
                    onHover(nil)
                }
            }
        }

        private func draw(in context: inout GraphicsContext, count: Int, cell: CGFloat) {
            let gutter = Self.gutter
            let range = Self.range(of: matrix, count: count) ?? 0...1
            let lowest = range.lowerBound
            let spread = range.upperBound - range.lowerBound
            let gap: CGFloat = cell > 12 ? 2 : 1
            let corner = min(3, cell * 0.2)

            // Sentence numbers along the top and left.
            let step = count <= 16 ? 1 : (count <= 30 ? 2 : 5)
            for index in stride(from: 0, to: count, by: step) {
                let isHovered = hovered.map { $0.row == index || $0.column == index } ?? false
                let label = Text("\(index + 1)")
                    .font(.system(size: 9, weight: isHovered ? .bold : .medium))
                    .foregroundStyle(isHovered ? Palette.ink : Palette.mutedInk)
                let middle = gutter + (CGFloat(index) + 0.5) * cell
                context.draw(label, at: CGPoint(x: middle, y: gutter / 2))
                context.draw(label, at: CGPoint(x: gutter / 2, y: middle))
            }

            for row in 0..<count {
                for column in 0..<count {
                    let rect = CGRect(
                        x: gutter + CGFloat(column) * cell,
                        y: gutter + CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    ).insetBy(dx: gap / 2, dy: gap / 2)
                    let color: Color
                    if row == column {
                        color = Color.white.opacity(0.1)
                    } else {
                        let value = matrix[row, column]
                        color = Palette.heat(spread > 1e-9 ? (value - lowest) / spread : 0.5)
                    }
                    let isDimmed = hovered.map { $0.row != row && $0.column != column } ?? false
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: corner, style: .continuous),
                        with: .color(isDimmed ? color.opacity(0.45) : color)
                    )
                }
            }

            if let hovered {
                for (row, column) in [(hovered.row, hovered.column), (hovered.column, hovered.row)] {
                    let rect = CGRect(
                        x: gutter + CGFloat(column) * cell,
                        y: gutter + CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    ).insetBy(dx: 0.5, dy: 0.5)
                    context.stroke(Path(roundedRect: rect, cornerRadius: corner + 1, style: .continuous), with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }

    // MARK: - Key phrases

    struct KeyphraseCard: View {
        let model: Model
        let analysis: Analysis
        @State private var hovered: Int?

        var body: some View {
            StageCard("Key phrases", symbol: "key", source: "ProseKit RAKE") {
                if analysis.keyphrases.isEmpty {
                    ChartCaption("No key phrases: every word here is a stopword.")
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(analysis.keyphrases.prefix(8)) { phrase in
                            row(phrase)
                        }
                    }
                    ChartCaption(analysis.isEnglish
                        ? "Stopwords and punctuation split the text into candidates; each word scores its degree over its frequency."
                        : "RAKE splits phrases at English stopwords, so other languages come out ragged.")
                }
            }
        }

        private func row(_ phrase: KeyphraseReading) -> some View {
            let best = max(analysis.keyphrases.first?.score ?? 1, 1)
            return HStack(spacing: 10) {
                Text("\(phrase.id + 1)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
                    .frame(width: 16, alignment: .trailing)
                Text(phrase.text)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if phrase.spans.count > 1 {
                    Text("\u{00D7}\(phrase.spans.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                }
                Spacer(minLength: 8)
                ValueBar(fraction: phrase.score / best, color: Palette.accent, height: 5)
                    .frame(width: 56)
                Text(Format.decimal(phrase.score))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered == phrase.id ? Color.white.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    hovered = phrase.id
                } else if hovered == phrase.id {
                    hovered = nil
                }
                model.hover(inside, spans: phrase.spans, from: "keyphrase:\(phrase.id)")
            }
        }
    }

    // MARK: - Grammar

    struct GrammarCard: View {
        let model: Model
        let analysis: Analysis

        var body: some View {
            StageCard("Parts of speech", symbol: "textformat.abc", source: "NLTagger") {
                if analysis.partsOfSpeech.isEmpty {
                    ChartCaption("No words to tag.")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        PartOfSpeechBar(shares: analysis.partsOfSpeech)
                            .frame(height: 12)
                        PartOfSpeechLegend(model: model, analysis: analysis)
                        ChartCaption("\(Format.percent(contentShare)) content words: the nouns, verbs, adjectives and adverbs that carry meaning. Hover a part of speech to find it.")
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                        LemmaTable(model: model, analysis: analysis)
                    }
                }
            }
        }

        private var contentShare: Double {
            analysis.partsOfSpeech.filter(\.partOfSpeech.isContentWord).reduce(0) { $0 + $1.share }
        }
    }

    /// Shares of each part of speech as one stacked bar, with a thin gap
    /// between segments.
    private struct PartOfSpeechBar: View {
        let shares: [PartOfSpeechShare]

        var body: some View {
            GeometryReader { proxy in
                let gap: CGFloat = 2
                let usable = max(proxy.size.width - gap * CGFloat(max(shares.count - 1, 0)), 0)
                HStack(spacing: gap) {
                    ForEach(shares) { share in
                        Rectangle()
                            .fill(Palette.partOfSpeech(share.partOfSpeech))
                            .frame(width: usable * CGFloat(share.share))
                            .help("\(share.partOfSpeech.title): \(share.count) (\(Format.percent(share.share)))")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }

    /// Words next to their dictionary forms, as NLTagger's lemma scheme
    /// reports them.
    private struct LemmaTable: View {
        let model: Model
        let analysis: Analysis

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("LEMMAS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.mutedInk)
                if analysis.lemmas.isEmpty {
                    ChartCaption("Every word is already in its dictionary form.")
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                        ForEach(rows, id: \.self) { row in
                            GridRow {
                                ForEach(row) { pair in
                                    cell(pair)
                                }
                            }
                        }
                    }
                }
            }
        }

        private var rows: [[LemmaPair]] {
            let pairs = Array(analysis.lemmas.prefix(10))
            return stride(from: 0, to: pairs.count, by: 2).map { Array(pairs[$0..<min($0 + 2, pairs.count)]) }
        }

        private func cell(_ pair: LemmaPair) -> some View {
            HStack(spacing: 5) {
                Text(pair.word)
                    .foregroundStyle(Palette.secondaryInk)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.mutedInk)
                Text(pair.lemma)
                    .foregroundStyle(Palette.ink)
                if pair.count > 1 {
                    Text("\u{00D7}\(pair.count)")
                        .font(.caption2)
                        .foregroundStyle(Palette.mutedInk)
                }
            }
            .font(.callout)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onHover { inside in
                let spans = analysis.words.filter { $0.text.lowercased() == pair.word }.map(\.span)
                model.hover(inside, spans: spans, from: "lemma:\(pair.word)")
            }
        }
    }
}
