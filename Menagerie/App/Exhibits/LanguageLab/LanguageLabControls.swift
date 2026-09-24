import ProseKit
import SwiftUI

// The control panel follows the system appearance, so these views use
// semantic colors rather than the stage palette.

extension LanguageLab {
    // MARK: - Samples

    struct SamplePicker: View {
        let model: Model

        var body: some View {
            ControlSection("Sample text") {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        tile(.news)
                        tile(.review)
                    }
                    GridRow {
                        tile(.literary)
                        tile(.multilingual)
                    }
                }
                if model.isEdited, let sample = model.sample {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                        Text("Edited")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Revert to \(sample.title)") {
                            model.load(sample)
                        }
                        .buttonStyle(.link)
                    }
                    .font(.caption)
                }
            }
        }

        private func tile(_ sample: Sample) -> some View {
            SampleTile(sample: sample, isSelected: model.sample == sample && !model.isEdited) {
                model.load(sample)
            }
        }
    }

    private struct SampleTile: View {
        let sample: Sample
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            let tint = Palette.accent
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            Button(action: action) {
                VStack(alignment: .leading, spacing: 3) {
                    Image(systemName: sample.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? tint : Color.secondary)
                        .frame(height: 20)
                    Text(sample.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(sample.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(isSelected ? tint.opacity(0.16) : Color.primary.opacity(isHovering ? 0.08 : 0.04)))
                .overlay(shape.strokeBorder(isSelected ? tint.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 1))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("Load \u{201C}\(sample.title)\u{201D}")
        }
    }

    // MARK: - Annotation mode

    struct ModePicker: View {
        let model: Model

        var body: some View {
            ControlSection("Annotate") {
                VStack(spacing: 2) {
                    ForEach(AnnotationMode.allCases) { mode in
                        ModeRow(mode: mode, isSelected: model.mode == mode) {
                            model.mode = mode
                        }
                    }
                }
            }
        }
    }

    private struct ModeRow: View {
        let mode: AnnotationMode
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            let tint = Palette.accent
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? tint : Color.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mode.title)
                            .font(.callout.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        Text(mode.caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? tint.opacity(0.14) : Color.primary.opacity(isHovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        }
    }

    // MARK: - Embeddings

    /// Neighbors and analogies in NaturalLanguage's English word embedding.
    struct EmbeddingPlayground: View {
        let model: Model

        var body: some View {
            ControlSection("Word embeddings") {
                VStack(alignment: .leading, spacing: 18) {
                    neighbors
                    analogies
                }
            }
        }

        private var neighbors: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nearest neighbors", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.callout.weight(.semibold))
                TextField("Any English word", text: Binding(
                    get: { model.neighborQuery },
                    set: { model.setNeighborQuery($0) }
                ))
                .textFieldStyle(.roundedBorder)

                switch model.neighbors {
                case .idle:
                    EmptyView()
                case .unavailable:
                    UnavailableNote()
                case .unknown(let words):
                    MissingWords(words: words)
                case .found(let neighbors):
                    NeighborList(neighbors: neighbors)
                }
            }
        }

        private var analogies: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Analogies", systemImage: "function")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Menu {
                        ForEach(AnalogyQuery.examples, id: \.self) { example in
                            Button(example.label) {
                                model.setAnalogyQuery(example)
                            }
                        }
                    } label: {
                        Text("Examples")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                }

                HStack(spacing: 5) {
                    field(\.base, placeholder: "king")
                    Text("\u{2212}").foregroundStyle(.secondary)
                    field(\.minus, placeholder: "man")
                    Text("+").foregroundStyle(.secondary)
                    field(\.plus, placeholder: "woman")
                }

                switch model.analogy {
                case .idle:
                    EmptyView()
                case .unavailable:
                    UnavailableNote()
                case .unknown(let words):
                    MissingWords(words: words)
                case .found(let answers):
                    AnalogyAnswers(answers: answers)
                }
            }
        }

        private func field(_ keyPath: WritableKeyPath<AnalogyQuery, String>, placeholder: String) -> some View {
            TextField(placeholder, text: Binding(
                get: { model.analogyQuery[keyPath: keyPath] },
                set: { value in
                    var query = model.analogyQuery
                    query[keyPath: keyPath] = value
                    model.setAnalogyQuery(query)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
        }
    }

    private struct NeighborList: View {
        let neighbors: [EmbeddingNeighbor]

        var body: some View {
            if neighbors.isEmpty {
                Text("No neighbors found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let closest = max(neighbors.map(\.similarity).max() ?? 1, 0.01)
                VStack(spacing: 5) {
                    ForEach(neighbors) { neighbor in
                        HStack(spacing: 8) {
                            Text(neighbor.word)
                                .font(.callout)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PanelMeter(fraction: neighbor.similarity / closest)
                                .frame(width: 70)
                            Text(Format.decimal(neighbor.distance, digits: 2))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                Text("Cosine distance: 0 is identical, and related words sit close together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct AnalogyAnswers: View {
        let answers: [EmbeddingNeighbor]

        var body: some View {
            if let best = answers.first {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("=")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(best.word)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        Spacer()
                        Text(Format.decimal(best.distance, digits: 2))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if answers.count > 1 {
                        Text("then " + answers.dropFirst().map(\.word).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("No answer found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct MissingWords: View {
        let words: [String]

        var body: some View {
            Text("Not in the vocabulary: " + words.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct UnavailableNote: View {
        var body: some View {
            Label("This Mac has no English word embedding installed.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A small bar for the control panel, in the exhibit's tint.
    private struct PanelMeter: View {
        let fraction: Double

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: max(3, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Readability

    struct ReadabilityPanel: View {
        let model: Model

        var body: some View {
            ControlSection("Readability") {
                if let analysis = model.analysis, !analysis.isEmpty {
                    let report = analysis.readability
                    ReadingEaseScale(score: report.fleschReadingEase)
                    VStack(spacing: 5) {
                        StatRow("Flesch reading ease", Format.decimal(report.fleschReadingEase))
                        ForEach(ReadabilityFormula.allCases.filter(\.isGradeLevel), id: \.self) { formula in
                            StatRow(formula.name, Format.grade(report.score(formula)))
                        }
                        Divider()
                        StatRow("Consensus grade", Format.grade(report.consensusGrade))
                    }
                    if !analysis.isEnglish {
                        Text("These formulas were calibrated on English, so other languages score oddly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Add some text to score it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Flesch Reading Ease on its 0–100 scale, with Flesch's label for the
    /// band the score falls in.
    private struct ReadingEaseScale: View {
        let score: Double

        var body: some View {
            let ease = ReadingEase(score: score)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ease.label)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(ease.typicalReader)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    let position = proxy.size.width * CGFloat(min(max(score, 0), 100) / 100)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Palette.accent.opacity(0.15), Palette.accent.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(height: 6)
                        Circle()
                            .fill(Palette.accent)
                            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .offset(x: min(max(position - 7, 0), proxy.size.width - 14))
                    }
                    .frame(height: proxy.size.height)
                }
                .frame(height: 14)
                HStack {
                    Text("Harder")
                    Spacer()
                    Text("Easier")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    struct StatisticsPanel: View {
        let model: Model

        var body: some View {
            ControlSection("Text statistics") {
                if let analysis = model.analysis, !analysis.isEmpty {
                    let report = analysis.readability
                    VStack(spacing: 5) {
                        StatRow("Words", report.wordCount.formatted())
                        StatRow("Sentences", report.sentenceCount.formatted())
                        StatRow("Characters", report.characterCount.formatted())
                        StatRow("Syllables", report.syllableCount.formatted())
                        StatRow("Words per sentence", Format.decimal(report.averageSentenceLength))
                        StatRow("Letters per word", Format.decimal(report.averageWordLength))
                        StatRow("Type–token ratio", Format.decimal(report.diversity.typeTokenRatio, digits: 2))
                        StatRow("MTLD", report.diversity.mtld.map { Format.decimal($0) } ?? "\u{2013}")
                        StatRow("Reading time", Format.duration(report.readingTime))
                    }
                } else {
                    Text("No text yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
