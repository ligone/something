import Foundation
import Observation

extension LanguageLab {
    /// The exhibit's state. Views read it and call its methods; the heavy
    /// lifting happens in `Analyzer` and `EmbeddingStore` off the main
    /// thread. Each kind of work keeps one task, cancelled and replaced when
    /// its input changes, so a burst of typing costs one analysis, not one
    /// per keystroke.
    @MainActor
    @Observable
    final class Model {
        // MARK: Text and analysis

        /// The text in the editor. It starts on the news sample so the
        /// editor is never blank, even for the first frame.
        private(set) var text = Sample.news.text
        /// The sample last loaded; the text may have been edited since.
        private(set) var sample: Sample? = .news
        var mode: AnnotationMode = .entities
        var similarityKind: SimilarityKind = .semantic
        /// Ranges to bring forward in the annotated text while the pointer
        /// rests on a chart, chip or row that refers to them.
        var highlight: TextHighlight?
        /// The latest finished analysis. It lags the editor by the debounce
        /// interval plus the analysis time.
        private(set) var analysis: Analysis?
        /// Sentence-embedding similarity. While a new one is computed, the
        /// previous result stays on screen, marked stale.
        private(set) var semanticSimilarity: SemanticSimilarity = .pending
        private(set) var isSemanticSimilarityStale = false
        private(set) var isAnalyzing = false

        // MARK: Embedding playground

        private(set) var neighborQuery = "coffee"
        private(set) var neighbors: NeighborsResult = .idle
        private(set) var analogyQuery = AnalogyQuery.kingAndQueen
        private(set) var analogy: AnalogyResult = .idle

        @ObservationIgnored private var analysisTask: Task<Void, Never>?
        @ObservationIgnored private var neighborsTask: Task<Void, Never>?
        @ObservationIgnored private var analogyTask: Task<Void, Never>?
        @ObservationIgnored private var hasStarted = false

        /// How long typing must pause before the text is analyzed again.
        private static let typingPause = Duration.milliseconds(300)
        /// The playground's text fields react a little faster.
        private static let queryPause = Duration.milliseconds(200)

        /// True when the text no longer matches the sample it came from.
        var isEdited: Bool {
            guard let sample else { return !text.isEmpty }
            return sample.text != text
        }

        /// Analyzes the opening text and fills the playground. Safe to call
        /// more than once.
        func start() {
            guard !hasStarted else { return }
            hasStarted = true
            analyze(after: nil)
            refreshNeighbors(after: nil)
            refreshAnalogy(after: nil)
        }

        func load(_ sample: Sample) {
            self.sample = sample
            highlight = nil
            guard sample.text != text else { return }
            text = sample.text
            analyze(after: nil)
        }

        /// Called by the editor on every keystroke.
        func edit(_ newText: String) {
            guard newText != text else { return }
            text = newText
            analyze(after: Self.typingPause)
        }

        func setNeighborQuery(_ query: String) {
            guard query != neighborQuery else { return }
            neighborQuery = query
            refreshNeighbors(after: Self.queryPause)
        }

        func setAnalogyQuery(_ query: AnalogyQuery) {
            guard query != analogyQuery else { return }
            analogyQuery = query
            refreshAnalogy(after: Self.queryPause)
        }

        /// Highlights stretches of the text on behalf of `source`, a name for
        /// the view doing it.
        func setHighlight(_ spans: [TextSpan], from source: String) {
            highlight = TextHighlight(spans: spans, source: source)
        }

        func highlightSentences(_ indices: [Int], from source: String) {
            guard let analysis else { return }
            setHighlight(analysis.spans(ofSentences: indices), from: source)
        }

        /// Clears the highlight, but only if `source` set it.
        func clearHighlight(from source: String) {
            if highlight?.source == source {
                highlight = nil
            }
        }

        /// Sets or clears a highlight as the pointer enters or leaves a view.
        func hover(_ isHovering: Bool, spans: [TextSpan], from source: String) {
            if isHovering {
                setHighlight(spans, from: source)
            } else {
                clearHighlight(from: source)
            }
        }

        // MARK: - Work

        private func analyze(after pause: Duration?) {
            analysisTask?.cancel()
            let snapshot = text
            isAnalyzing = true
            analysisTask = Task { [weak self] in
                if let pause {
                    try? await Task.sleep(for: pause)
                    if Task.isCancelled { return }
                }
                guard let result = await Analyzer.analyze(snapshot), !Task.isCancelled, let self else { return }
                self.analysis = result
                self.highlight = nil
                self.isAnalyzing = false

                // The sentence embedding is slower, so its heatmap catches up
                // after everything else has appeared.
                self.isSemanticSimilarityStale = true
                let semantic = await Analyzer.semanticSimilarity(of: result)
                guard !Task.isCancelled else { return }
                self.semanticSimilarity = semantic
                self.isSemanticSimilarityStale = false
            }
        }

        private func refreshNeighbors(after pause: Duration?) {
            neighborsTask?.cancel()
            let query = neighborQuery
            neighborsTask = Task { [weak self] in
                if let pause {
                    try? await Task.sleep(for: pause)
                    if Task.isCancelled { return }
                }
                let result = await EmbeddingStore.shared.neighbors(of: query, count: 8)
                guard !Task.isCancelled, let self else { return }
                self.neighbors = result
            }
        }

        private func refreshAnalogy(after pause: Duration?) {
            analogyTask?.cancel()
            let query = analogyQuery
            analogyTask = Task { [weak self] in
                if let pause {
                    try? await Task.sleep(for: pause)
                    if Task.isCancelled { return }
                }
                let result = await EmbeddingStore.shared.analogy(query, count: 5)
                guard !Task.isCancelled, let self else { return }
                self.analogy = result
            }
        }
    }
}
