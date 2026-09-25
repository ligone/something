import SwiftUI

extension LanguageLab {
    /// The dark stage. Wide windows put the text beside the charts, so a
    /// chart and the sentences it points at are visible together; narrow ones
    /// stack everything in one scrolling column.
    struct StageView: View {
        let model: Model

        /// Room for the pills that float over the top of the stage.
        static let topInset: CGFloat = 54
        /// Room for the hint that floats over the bottom.
        static let bottomInset: CGFloat = 48

        var body: some View {
            GeometryReader { proxy in
                if proxy.size.width >= 880 {
                    SideBySideStage(model: model, size: proxy.size)
                } else {
                    StackedStage(model: model)
                }
            }
            .stageHUD(.topLeading) {
                StagePills(model: model)
            }
            .stageHint("Edit the text and everything updates \u{00B7} Hover a chart to find its words")
        }
    }

    private struct SideBySideStage: View {
        let model: Model
        let size: CGSize

        var body: some View {
            let textWidth = min(max(size.width * 0.47, 400), 660)
            let editorHeight = min(max(size.height * 0.28, 150), 250)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 14) {
                    EditorCard(model: model)
                        .frame(height: editorHeight)
                    AnnotatedTextCard(model: model, fillsHeight: true)
                }
                .frame(width: textWidth)
                .padding(.bottom, StageView.bottomInset)

                ScrollView {
                    InsightCards(model: model)
                        .padding(.bottom, StageView.bottomInset + 12)
                }
                .scrollIndicators(.never)
            }
            .padding(.top, StageView.topInset)
            .padding(.horizontal, 18)
        }
    }

    private struct StackedStage: View {
        let model: Model

        var body: some View {
            ScrollView {
                VStack(spacing: 14) {
                    EditorCard(model: model)
                        .frame(height: 170)
                    AnnotatedTextCard(model: model, fillsHeight: false)
                    InsightCards(model: model)
                }
                .padding(.top, StageView.topInset)
                .padding(.horizontal, 16)
                .padding(.bottom, StageView.bottomInset + 12)
            }
            .scrollIndicators(.never)
        }
    }

    /// The charts, in as many columns as fit. A text that mixes languages
    /// leads with the language card; otherwise sentiment and similarity,
    /// the most telling charts, come first.
    private struct InsightCards: View {
        let model: Model

        var body: some View {
            if let analysis = model.analysis, !analysis.isEmpty {
                let isMultilingual = analysis.sentenceLanguages.count > 1
                MasonryLayout(minimumColumnWidth: 330, maximumColumns: 3, spacing: 14) {
                    if isMultilingual {
                        LanguageCard(model: model, analysis: analysis)
                    }
                    SentimentCard(model: model, analysis: analysis)
                    SimilarityCard(model: model, analysis: analysis)
                    if !isMultilingual {
                        LanguageCard(model: model, analysis: analysis)
                    }
                    KeyphraseCard(model: model, analysis: analysis)
                    GrammarCard(model: model, analysis: analysis)
                }
                .opacity(model.isAnalyzing ? 0.7 : 1)
                .animation(.easeOut(duration: 0.2), value: model.isAnalyzing)
            }
        }
    }

    /// Headline numbers floating over the top of the stage.
    private struct StagePills: View {
        let model: Model

        var body: some View {
            if let analysis = model.analysis, !analysis.isEmpty {
                HStack(spacing: 8) {
                    StatPill("Language", analysis.language.dominant.map(LanguageNames.name) ?? "Unknown")
                    StatPill("Words", analysis.readability.wordCount.formatted())
                    if let sentiment = analysis.overallSentiment {
                        StatPill("Sentiment", Format.signed(sentiment))
                    }
                    if analysis.isEnglish {
                        StatPill("Grade", Format.grade(analysis.readability.consensusGrade))
                    }
                }
            }
        }
    }

    /// The editable text, styled for the dark stage.
    private struct EditorCard: View {
        let model: Model

        var body: some View {
            StageCard("Text", symbol: "square.and.pencil") {
                HStack(spacing: 8) {
                    if model.isAnalyzing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text("\(model.text.count.formatted()) characters")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.mutedInk)
                }
            } content: {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(get: { model.text }, set: { model.edit($0) }))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.automatic)
                    if model.text.isEmpty {
                        Text("Type or paste some text…")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Palette.mutedInk)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, -5)
                .frame(maxHeight: .infinity)
            }
        }
    }
}
