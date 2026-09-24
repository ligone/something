import Foundation
import ProseKit

extension LanguageLab {
    /// A stretch of the analyzed text in UTF-16 offsets. NaturalLanguage
    /// works in UTF-16, and plain integers stay valid however the text is
    /// sliced, so every range the stage draws is stored this way.
    typealias TextSpan = Range<Int>

    /// Everything the stage shows about one snapshot of the text. Built off
    /// the main thread by `Analyzer`, so it holds only plain values.
    struct Analysis: Sendable {
        /// The exact text analyzed. Every span below indexes into it.
        let text: String
        let language: LanguageReading
        let sentences: [SentenceReading]
        let words: [WordReading]
        let entities: [EntityReading]
        let entityGroups: [EntityGroup]
        let keyphrases: [KeyphraseReading]
        let partsOfSpeech: [PartOfSpeechShare]
        let lemmas: [LemmaPair]
        let readability: ReadabilityReport
        let lexicalSimilarity: SimilarityMatrix

        /// Sentence scores averaged, weighting each by its length; nil when no
        /// sentence could be scored.
        var overallSentiment: Double? {
            var total = 0.0
            var weight = 0.0
            for sentence in sentences {
                guard let score = sentence.sentiment else { continue }
                let length = Double(max(sentence.span.count, 1))
                total += score * length
                weight += length
            }
            return weight > 0 ? total / weight : nil
        }

        /// The languages found sentence by sentence, in order of first
        /// appearance.
        var sentenceLanguages: [String] {
            var seen: [String] = []
            for code in sentences.compactMap(\.languageCode) where !seen.contains(code) {
                seen.append(code)
            }
            return seen
        }

        /// True unless the text is clearly in another language; the
        /// readability formulas and the stopword list assume English.
        var isEnglish: Bool {
            language.dominant == nil || language.dominant == "en"
        }

        var isEmpty: Bool {
            readability.isEmpty
        }

        /// The spans of the given sentences, for highlighting.
        func spans(ofSentences indices: [Int]) -> [TextSpan] {
            indices.compactMap { sentences.indices.contains($0) ? sentences[$0].span : nil }
        }
    }

    struct LanguageReading: Sendable {
        /// BCP 47 code of the most likely language, such as "en" or "zh-Hans".
        let dominant: String?
        /// The recognizer's hypotheses, most likely first.
        let hypotheses: [LanguageGuess]
    }

    struct LanguageGuess: Sendable, Hashable, Identifiable {
        let code: String
        let probability: Double
        var id: String { code }
    }

    struct SentenceReading: Sendable, Identifiable {
        /// The sentence's position in the text, from 0.
        let id: Int
        let span: TextSpan
        let text: String
        /// NLTagger's score from −1 (negative) to 1 (positive); nil when
        /// there is no sentiment model for the sentence's language.
        let sentiment: Double?
        let languageCode: String?
        let languageConfidence: Double
        /// ProseKit's Flesch–Kincaid grade for this sentence alone.
        let gradeLevel: Double
    }

    struct WordReading: Sendable {
        let span: TextSpan
        let text: String
        let partOfSpeech: PartOfSpeech?
        let lemma: String?
        /// ProseKit's syllable count.
        let syllables: Int
    }

    struct EntityReading: Sendable, Hashable {
        let span: TextSpan
        let text: String
        let kind: EntityKind
    }

    /// One named thing and everywhere it is mentioned. A surname alone
    /// ("Delgado") joins the full name mentioned elsewhere ("Maria Delgado").
    struct EntityCluster: Sendable, Hashable, Identifiable {
        let name: String
        let kind: EntityKind
        let spans: [TextSpan]
        var id: String { "\(kind.rawValue):\(name)" }
    }

    struct EntityGroup: Sendable, Identifiable {
        let kind: EntityKind
        let clusters: [EntityCluster]
        var id: EntityKind { kind }
    }

    struct KeyphraseReading: Sendable, Identifiable {
        /// Rank, from 0.
        let id: Int
        let text: String
        let score: Double
        let spans: [TextSpan]
    }

    struct PartOfSpeechShare: Sendable, Identifiable {
        let partOfSpeech: PartOfSpeech
        let count: Int
        let share: Double
        var id: PartOfSpeech { partOfSpeech }
    }

    /// A word whose dictionary form differs from how it is written.
    struct LemmaPair: Sendable, Hashable, Identifiable {
        let word: String
        let lemma: String
        let count: Int
        var id: String { word }
    }

    /// The sentence-embedding similarity, which arrives after the rest of
    /// the analysis because the model takes a moment to load.
    enum SemanticSimilarity: Sendable {
        case pending
        case unavailable(reason: String)
        case ready(SimilarityMatrix)
    }

    /// Ranges of the analyzed text to bring forward while the pointer rests
    /// on something that refers to them, such as a chart bar or a chip.
    struct TextHighlight: Equatable {
        var spans: [TextSpan]
        /// Which view set the highlight. Only that view may clear it, so
        /// gliding from one chip to the next never flickers.
        var source: String

        func contains(_ offset: Int) -> Bool {
            spans.contains { $0.contains(offset) }
        }
    }

    // MARK: - Categories

    enum EntityKind: String, CaseIterable, Sendable, Identifiable {
        case person, place, organization

        var id: String { rawValue }

        var title: String {
            switch self {
            case .person: "People"
            case .place: "Places"
            case .organization: "Organizations"
            }
        }

        var symbol: String {
            switch self {
            case .person: "person.fill"
            case .place: "mappin.and.ellipse"
            case .organization: "building.2.fill"
            }
        }
    }

    /// Parts of speech, folded from NaturalLanguage's lexical classes into
    /// the groups a reader cares about.
    enum PartOfSpeech: String, CaseIterable, Sendable, Identifiable {
        case noun, verb, adjective, adverb, pronoun, number, function, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .noun: "Nouns"
            case .verb: "Verbs"
            case .adjective: "Adjectives"
            case .adverb: "Adverbs"
            case .pronoun: "Pronouns"
            case .number: "Numbers"
            case .function: "Function words"
            case .other: "Other"
            }
        }

        /// Nouns, verbs, adjectives and adverbs carry a text's content.
        var isContentWord: Bool {
            switch self {
            case .noun, .verb, .adjective, .adverb: true
            default: false
            }
        }
    }

    enum AnnotationMode: String, CaseIterable, Identifiable {
        case entities, partsOfSpeech, sentiment, keyphrases, difficulty

        var id: String { rawValue }

        var title: String {
            switch self {
            case .entities: "Entities"
            case .partsOfSpeech: "Parts of speech"
            case .sentiment: "Sentiment"
            case .keyphrases: "Key phrases"
            case .difficulty: "Difficulty"
            }
        }

        var caption: String {
            switch self {
            case .entities: "People, places and organizations"
            case .partsOfSpeech: "Every word colored by its role"
            case .sentiment: "Each sentence tinted by its mood"
            case .keyphrases: "RAKE's highest-scoring phrases"
            case .difficulty: "Hard sentences and long words"
            }
        }

        var symbol: String {
            switch self {
            case .entities: "person.text.rectangle"
            case .partsOfSpeech: "textformat.abc"
            case .sentiment: "theatermasks"
            case .keyphrases: "key"
            case .difficulty: "graduationcap"
            }
        }
    }

    enum SimilarityKind: String, CaseIterable, Identifiable {
        case semantic, lexical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .semantic: "Meaning"
            case .lexical: "Words"
            }
        }
    }
}
