import SwiftUI

extension LanguageLab {
    /// Renders the analyzed text as an `AttributedString` styled for the
    /// current annotation mode.
    ///
    /// Each mode contributes layers of styled runs (entity backgrounds, word
    /// colors, sentence tints, underlines). The text is cut at every run
    /// boundary, and each piece takes the styles of the runs covering it.
    /// While a highlight is active, everything outside it fades back.
    enum AnnotatedText {
        static let fontSize: CGFloat = 15

        static func build(_ analysis: Analysis, mode: AnnotationMode, highlight: TextHighlight?) -> AttributedString {
            var layers: [[Run]] = []
            var tags: [Int: String] = [:]

            switch mode {
            case .entities:
                layers.append(analysis.entities.map { entity in
                    Run(span: entity.span, style: Style(foreground: .white, background: Palette.entity(entity.kind).opacity(0.45)))
                })
            case .partsOfSpeech:
                layers.append(analysis.words.map { word in
                    Run(span: word.span, style: Style(foreground: Palette.partOfSpeechText(word.partOfSpeech)))
                })
            case .sentiment:
                layers.append(analysis.sentences.compactMap { sentence in
                    guard let score = sentence.sentiment else { return nil }
                    let tint = Palette.sentiment(score).opacity(0.14 + 0.36 * abs(score))
                    return Run(span: sentence.span, style: Style(background: tint))
                })
                for sentence in analysis.sentences {
                    if let score = sentence.sentiment {
                        tags[sentence.span.upperBound] = Format.signed(score, digits: 1)
                    }
                }
            case .keyphrases:
                layers.append(keyphraseRuns(analysis.keyphrases))
            case .difficulty:
                layers.append(analysis.sentences.compactMap { sentence in
                    guard let color = Palette.difficulty(ofGrade: sentence.gradeLevel) else { return nil }
                    return Run(span: sentence.span, style: Style(background: color.opacity(0.24)))
                })
                layers.append(analysis.words
                    .filter { $0.syllables >= 3 && !$0.text.contains(where: \.isNumber) }
                    .map { Run(span: $0.span, style: Style(underline: Palette.longWord)) })
                for sentence in analysis.sentences {
                    tags[sentence.span.upperBound] = "G\(Int(max(0, sentence.gradeLevel).rounded()))"
                }
            }

            let sortedLayers = layers.map { layer in layer.sorted { $0.span.lowerBound < $1.span.lowerBound } }
            return assemble(analysis.text, layers: sortedLayers, tags: tags, highlight: highlight)
        }

        // MARK: - Styles

        struct Style {
            var foreground: Color?
            var background: Color?
            var underline: Color?

            mutating func merge(_ other: Style) {
                if let foreground = other.foreground { self.foreground = foreground }
                if let background = other.background { self.background = background }
                if let underline = other.underline { self.underline = underline }
            }
        }

        struct Run {
            let span: TextSpan
            let style: Style
        }

        private enum Emphasis {
            case plain, focused, dimmed
        }

        /// The top phrases' occurrences, brighter for higher ranks. Where two
        /// phrases overlap, the better-ranked one wins.
        private static func keyphraseRuns(_ keyphrases: [KeyphraseReading]) -> [Run] {
            var runs: [Run] = []
            for phrase in keyphrases.prefix(8) {
                let tint = Palette.accent.opacity(max(0.18, 0.5 - 0.045 * Double(phrase.id)))
                for span in phrase.spans where !runs.contains(where: { $0.span.overlaps(span) }) {
                    runs.append(Run(span: span, style: Style(foreground: .white, background: tint)))
                }
            }
            return runs
        }

        // MARK: - Assembly

        private static func assemble(
            _ text: String,
            layers: [[Run]],
            tags: [Int: String],
            highlight: TextHighlight?
        ) -> AttributedString {
            let utf16 = text.utf16
            let length = utf16.count
            func clamp(_ offset: Int) -> Int { min(max(offset, 0), length) }

            var cuts: Set<Int> = [0, length]
            for layer in layers {
                for run in layer {
                    cuts.insert(clamp(run.span.lowerBound))
                    cuts.insert(clamp(run.span.upperBound))
                }
            }
            for span in highlight?.spans ?? [] {
                cuts.insert(clamp(span.lowerBound))
                cuts.insert(clamp(span.upperBound))
            }
            for offset in tags.keys {
                cuts.insert(clamp(offset))
            }
            let boundaries = cuts.sorted()

            var result = AttributedString()
            var cursor = text.startIndex
            var positions = [Int](repeating: 0, count: layers.count)

            for (start, end) in zip(boundaries, boundaries.dropFirst()) {
                if let tag = tags[start] {
                    result.append(tagText(tag, dimmed: highlight.map { !$0.contains(start - 1) } ?? false))
                }
                let next = utf16.index(cursor, offsetBy: end - start)

                var style = Style()
                for (index, layer) in layers.enumerated() {
                    var position = positions[index]
                    while position < layer.count, layer[position].span.upperBound <= start {
                        position += 1
                    }
                    positions[index] = position
                    if position < layer.count, layer[position].span.lowerBound <= start {
                        style.merge(layer[position].style)
                    }
                }

                var piece = AttributedString(String(text[cursor..<next]))
                let emphasis: Emphasis = highlight.map { $0.contains(start) ? .focused : .dimmed } ?? .plain
                apply(style, emphasis, to: &piece)
                result.append(piece)
                cursor = next
            }
            if let tag = tags[length] {
                result.append(tagText(tag, dimmed: highlight.map { !$0.contains(length - 1) } ?? false))
            }
            return result
        }

        private static func apply(_ style: Style, _ emphasis: Emphasis, to piece: inout AttributedString) {
            var foreground = style.foreground ?? Palette.ink
            var background = style.background
            var underline = style.underline
            switch emphasis {
            case .plain:
                break
            case .focused:
                foreground = style.foreground ?? .white
                if background == nil {
                    background = Color.white.opacity(0.13)
                }
            case .dimmed:
                foreground = foreground.opacity(0.3)
                background = background?.opacity(0.25)
                underline = underline?.opacity(0.3)
            }

            piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = foreground
            if let background {
                piece[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = background
            }
            if let underline {
                piece[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = Text.LineStyle(pattern: .solid, color: underline)
            }
        }

        /// A small raised label after a sentence, such as its sentiment score.
        private static func tagText(_ label: String, dimmed: Bool) -> AttributedString {
            var tag = AttributedString("\u{2009}\(label)")
            tag[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = .system(size: 9.5, weight: .semibold, design: .rounded)
            tag[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.white.opacity(dimmed ? 0.2 : 0.55)
            tag[AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute.self] = 4
            return tag
        }
    }

    /// The text rendered with the current annotations, plus the legend for
    /// the mode.
    struct AnnotatedTextCard: View {
        let model: Model
        /// In the side-by-side layout the card fills its column and the text
        /// scrolls inside it.
        let fillsHeight: Bool

        var body: some View {
            StageCard("Annotated", symbol: model.mode.symbol, source: model.mode.source) {
                Text(model.mode.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.secondaryInk)
            } content: {
                if let analysis = model.analysis, !analysis.isEmpty {
                    renderedText(analysis)
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                    ModeLegend(model: model, analysis: analysis)
                } else if model.analysis == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : 120)
                } else {
                    ChartCaption("Type or paste some text to see it annotated.")
                        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : 120)
                }
            }
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        }

        /// While a newer analysis is on its way, the last one stays up, dimmed.
        @ViewBuilder
        private func renderedText(_ analysis: Analysis) -> some View {
            let text = Text(AnnotatedText.build(analysis, mode: model.mode, highlight: model.highlight))
                .font(.system(size: AnnotatedText.fontSize, design: .serif))
                .lineSpacing(7)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(model.isAnalyzing ? 0.6 : 1)
                .animation(.easeOut(duration: 0.2), value: model.isAnalyzing)
            if fillsHeight {
                ScrollView {
                    text.padding(.trailing, 6)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: .infinity)
            } else {
                text
            }
        }
    }

    /// The key to the annotations, which doubles as a way to find things:
    /// hovering an item highlights its words in the text.
    struct ModeLegend: View {
        let model: Model
        let analysis: Analysis

        var body: some View {
            switch model.mode {
            case .entities:
                EntityChips(model: model, groups: analysis.entityGroups)
            case .partsOfSpeech:
                PartOfSpeechLegend(model: model, analysis: analysis)
            case .sentiment:
                SentimentLegend()
            case .keyphrases:
                KeyphraseChips(model: model, keyphrases: analysis.keyphrases)
            case .difficulty:
                DifficultyLegend(analysis: analysis)
            }
        }
    }

    struct EntityChips: View {
        let model: Model
        let groups: [EntityGroup]

        var body: some View {
            if groups.isEmpty {
                ChartCaption("No people, places or organizations found.")
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(groups) { group in
                        HStack(alignment: .top, spacing: 10) {
                            HStack(spacing: 6) {
                                Swatch(color: Palette.entity(group.kind))
                                Text(group.kind.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                            .frame(width: 100, alignment: .leading)
                            .padding(.top, 4)

                            FlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(group.clusters) { cluster in
                                    Chip(
                                        text: cluster.name,
                                        count: cluster.spans.count,
                                        tint: Palette.entity(cluster.kind)
                                    ) { hovering in
                                        model.hover(hovering, spans: cluster.spans, from: "entity:\(cluster.id)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// A capsule naming something in the text. Hovering it highlights every
    /// occurrence.
    struct Chip: View {
        let text: String
        var count = 1
        let tint: Color
        let onHover: (Bool) -> Void
        @State private var isHovering = false

        var body: some View {
            HStack(spacing: 5) {
                Text(text)
                    .lineLimit(1)
                if count > 1 {
                    Text("×\(count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(isHovering ? 0.55 : 0.3)))
            .overlay(Capsule().strokeBorder(tint.opacity(isHovering ? 0.9 : 0.55), lineWidth: 1))
            .contentShape(Capsule())
            .onHover { hovering in
                isHovering = hovering
                onHover(hovering)
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }

    struct PartOfSpeechLegend: View {
        let model: Model
        let analysis: Analysis

        var body: some View {
            FlowLayout(spacing: 12, lineSpacing: 7) {
                ForEach(analysis.partsOfSpeech) { share in
                    HStack(spacing: 5) {
                        Swatch(color: Palette.partOfSpeech(share.partOfSpeech))
                        Text(share.partOfSpeech.title)
                            .foregroundStyle(Palette.ink)
                        Text(Format.percent(share.share))
                            .monospacedDigit()
                            .foregroundStyle(Palette.mutedInk)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        let spans = analysis.words.filter { $0.partOfSpeech == share.partOfSpeech }.map(\.span)
                        model.hover(hovering, spans: spans, from: "pos:\(share.partOfSpeech.rawValue)")
                    }
                }
            }
        }
    }

    struct SentimentLegend: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Negative")
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Palette.negative, Palette.neutral, Palette.positive],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: 120, height: 6)
                    Text("Positive")
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                ChartCaption("Each sentence is tinted by its score from NLTagger, shown after it from −1 to +1.")
            }
        }
    }

    struct KeyphraseChips: View {
        let model: Model
        let keyphrases: [KeyphraseReading]

        var body: some View {
            if keyphrases.isEmpty {
                ChartCaption("No key phrases found.")
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(keyphrases.prefix(8)) { phrase in
                        Chip(text: phrase.text, count: phrase.spans.count, tint: Palette.accent) { hovering in
                            model.hover(hovering, spans: phrase.spans, from: "keyphrase-chip:\(phrase.id)")
                        }
                    }
                }
            }
        }
    }

    struct DifficultyLegend: View {
        let analysis: Analysis

        private var hardCount: Int {
            analysis.sentences.filter { $0.gradeLevel >= 10 }.count
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 14) {
                    key(Palette.hard, "Grade 10+", symbol: "exclamationmark.triangle.fill")
                    key(Palette.veryHard, "Grade 14+", symbol: "exclamationmark.octagon.fill")
                    HStack(spacing: 5) {
                        Text("long")
                            .underline(color: Palette.longWord)
                            .foregroundStyle(Palette.ink)
                        Text("3+ syllables")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .font(.caption)
                ChartCaption("\(hardCount) of \(analysis.sentences.count) sentences read at grade 10 or above. G marks each sentence’s Flesch–Kincaid grade.")
            }
        }

        private func key(_ color: Color, _ label: String, symbol: String) -> some View {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(label)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

extension LanguageLab.AnnotationMode {
    /// What produces the annotation.
    var source: String {
        switch self {
        case .entities: "NLTagger .nameType"
        case .partsOfSpeech: "NLTagger .lexicalClass"
        case .sentiment: "NLTagger .sentimentScore"
        case .keyphrases: "ProseKit RAKE"
        case .difficulty: "ProseKit"
        }
    }
}
