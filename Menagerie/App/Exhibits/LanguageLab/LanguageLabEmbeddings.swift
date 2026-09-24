import Foundation
import NaturalLanguage
import ProseKit

extension LanguageLab {
    /// Owns the NaturalLanguage embeddings. Each takes a moment to load and
    /// isn't documented as thread-safe, so this actor loads each one once,
    /// keeps it, and serializes every use.
    actor EmbeddingStore {
        static let shared = EmbeddingStore()

        /// The most sentences compared in the similarity heatmap.
        static let sentenceLimit = 40

        private var wordEmbedding: NLEmbedding?
        private var hasLoadedWordEmbedding = false
        private var sentenceEmbedding: NLEmbedding?
        private var hasLoadedSentenceEmbedding = false

        // MARK: - Words

        /// The words nearest to `query` in the English word embedding.
        func neighbors(of query: String, count: Int) -> NeighborsResult {
            let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return .idle }
            guard let embedding = loadWordEmbedding() else { return .unavailable }
            guard let known = vocabularyForm(of: word, in: embedding) else { return .unknown([word]) }
            let neighbors = embedding.neighbors(for: known, maximumCount: count + 1, distanceType: .cosine)
                .filter { $0.0.lowercased() != known.lowercased() }
                .prefix(count)
                .map { EmbeddingNeighbor(word: $0.0, distance: $0.1) }
            return .found(Array(neighbors))
        }

        /// Solves "b is to a as c is to what?" by vector arithmetic: the words
        /// nearest to a − b + c, leaving out the three inputs.
        func analogy(_ query: AnalogyQuery, count: Int) -> AnalogyResult {
            let terms = [query.base, query.minus, query.plus].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard terms.allSatisfy({ !$0.isEmpty }) else { return .idle }
            guard let embedding = loadWordEmbedding() else { return .unavailable }

            let known = terms.map { vocabularyForm(of: $0, in: embedding) }
            let missing = zip(terms, known).filter { $0.1 == nil }.map(\.0)
            guard missing.isEmpty else { return .unknown(missing) }
            let vectors = known.compactMap { word in word.flatMap { embedding.vector(for: $0) } }
            guard vectors.count == 3 else { return .unknown(terms) }

            let target = EmbeddingMath.analogy(vectors[0], minus: vectors[1], plus: vectors[2])
            let inputs = Set(known.compactMap { $0?.lowercased() })
            let answers = embedding.neighbors(for: target, maximumCount: count + inputs.count, distanceType: .cosine)
                .filter { !inputs.contains($0.0.lowercased()) }
                .prefix(count)
                .map { EmbeddingNeighbor(word: $0.0, distance: $0.1) }
            return .found(Array(answers))
        }

        /// The word as the embedding's vocabulary spells it: as typed, in
        /// lowercase, or capitalized.
        private func vocabularyForm(of word: String, in embedding: NLEmbedding) -> String? {
            [word, word.lowercased(), word.capitalized].first { embedding.contains($0) }
        }

        private func loadWordEmbedding() -> NLEmbedding? {
            if !hasLoadedWordEmbedding {
                wordEmbedding = NLEmbedding.wordEmbedding(for: .english)
                hasLoadedWordEmbedding = true
            }
            return wordEmbedding
        }

        // MARK: - Sentences

        /// Cosine similarity between sentence vectors. Sentences that aren't
        /// English get no vector and score 0 against everything.
        func sentenceSimilarity(of sentences: [(text: String, isEnglish: Bool)]) -> SemanticSimilarity {
            guard sentences.count >= 2 else {
                return .unavailable(reason: "Needs at least two sentences.")
            }
            guard let embedding = loadSentenceEmbedding() else {
                return .unavailable(reason: "This Mac has no English sentence embedding, so the heatmap compares words instead.")
            }
            var vectors: [[Double]] = []
            for sentence in sentences.prefix(Self.sentenceLimit) {
                if Task.isCancelled { return .pending }
                vectors.append(sentence.isEnglish ? embedding.vector(for: sentence.text) ?? [] : [])
            }
            guard vectors.filter({ !$0.isEmpty }).count >= 2 else {
                return .unavailable(reason: "The sentence embedding reads English only, so the heatmap compares words instead.")
            }
            return .ready(SimilarityMatrix(cosineOf: vectors))
        }

        private func loadSentenceEmbedding() -> NLEmbedding? {
            if !hasLoadedSentenceEmbedding {
                sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
                hasLoadedSentenceEmbedding = true
            }
            return sentenceEmbedding
        }
    }

    struct EmbeddingNeighbor: Sendable, Hashable, Identifiable {
        let word: String
        /// Cosine distance: 0 for the same direction, up to 2 for opposite.
        let distance: Double
        var id: String { word }

        /// Cosine similarity, 1 − distance.
        var similarity: Double { 1 - distance }
    }

    enum NeighborsResult: Sendable, Equatable {
        case idle
        case unavailable
        case unknown([String])
        case found([EmbeddingNeighbor])
    }

    enum AnalogyResult: Sendable, Equatable {
        case idle
        case unavailable
        case unknown([String])
        case found([EmbeddingNeighbor])
    }

    /// "base − minus + plus", as in king − man + woman.
    struct AnalogyQuery: Hashable, Sendable {
        var base: String
        var minus: String
        var plus: String

        var label: String {
            "\(base) \u{2212} \(minus) + \(plus)"
        }

        static let kingAndQueen = AnalogyQuery(base: "king", minus: "man", plus: "woman")

        static let examples: [AnalogyQuery] = [
            kingAndQueen,
            AnalogyQuery(base: "Paris", minus: "France", plus: "Italy"),
            AnalogyQuery(base: "walked", minus: "walk", plus: "swim"),
            AnalogyQuery(base: "bigger", minus: "big", plus: "small"),
            AnalogyQuery(base: "puppy", minus: "dog", plus: "cat"),
            AnalogyQuery(base: "brother", minus: "man", plus: "woman"),
        ]
    }
}
