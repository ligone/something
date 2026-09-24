import Foundation
import NaturalLanguage
import ProseKit

extension LanguageLab {
    /// Turns text into an `Analysis`. NaturalLanguage's taggers and
    /// recognizers aren't thread-safe, so every run creates its own and
    /// works on one background task from start to finish.
    enum Analyzer {
        /// Analyzes `text` on a detached background task. Returns nil when the
        /// calling task is cancelled first, which happens whenever the text
        /// changes again.
        static func analyze(_ text: String) async -> Analysis? {
            let work = Task.detached(priority: .userInitiated) {
                makeAnalysis(of: text)
            }
            return await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
        }

        /// Sentence-embedding similarity between the analysis's sentences.
        /// Only English sentences are embedded, because the model is English.
        static func semanticSimilarity(of analysis: Analysis) async -> SemanticSimilarity {
            let sentences = analysis.sentences.map { sentence in
                (text: sentence.text, isEnglish: sentence.languageCode == nil || sentence.languageCode == "en")
            }
            return await EmbeddingStore.shared.sentenceSimilarity(of: sentences)
        }

        private static func makeAnalysis(of text: String) -> Analysis? {
            let readability = ReadabilityReport(text: text)
            let language = recognizeLanguage(of: text)
            let sentenceTexts = readability.sentences.map(\.text)
            let sentenceLanguages = recognizeLanguages(of: sentenceTexts, fallback: language.dominant)
            guard !Task.isCancelled else { return nil }

            let sentiments = scoreSentiment(of: sentenceTexts)
            guard !Task.isCancelled else { return nil }

            let sentences = readability.sentences.enumerated().map { index, sentence in
                SentenceReading(
                    id: index,
                    span: span(of: sentence.range, in: text),
                    text: sentence.text,
                    sentiment: sentiments[index],
                    languageCode: sentenceLanguages[index]?.code,
                    languageConfidence: sentenceLanguages[index]?.probability ?? 0,
                    gradeLevel: sentence.gradeLevel
                )
            }

            let (words, entities) = tagWords(of: text)
            guard !Task.isCancelled else { return nil }

            let keyphrases = KeywordExtractor().keyphrases(in: text).prefix(12).enumerated().map { rank, phrase in
                KeyphraseReading(
                    id: rank,
                    text: phrase.text,
                    score: phrase.score,
                    spans: phrase.occurrences.map { span(of: $0, in: text) }
                )
            }

            return Analysis(
                text: text,
                language: language,
                sentences: sentences,
                words: words,
                entities: entities,
                entityGroups: groupEntities(entities),
                keyphrases: keyphrases,
                partsOfSpeech: shares(of: words),
                lemmas: lemmaPairs(of: words),
                readability: readability,
                lexicalSimilarity: SimilarityMatrix.lexical(sentences: sentenceTexts)
            )
        }

        // MARK: - Language

        private static func recognizeLanguage(of text: String) -> LanguageReading {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 6)
                .filter { $0.key != .undetermined }
                .map { LanguageGuess(code: $0.key.rawValue, probability: $0.value) }
                .sorted { $0.probability > $1.probability }
            let dominant = recognizer.dominantLanguage.flatMap { $0 == .undetermined ? nil : $0.rawValue }
            return LanguageReading(dominant: dominant, hypotheses: hypotheses)
        }

        /// The language of each sentence. Very short or uncertain sentences
        /// take the text's dominant language rather than a wild guess.
        private static func recognizeLanguages(of sentences: [String], fallback: String?) -> [LanguageGuess?] {
            sentences.map { sentence in
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(sentence)
                let hypotheses = recognizer.languageHypotheses(withMaximum: 8)
                if let best = hypotheses.max(by: { $0.value < $1.value }),
                   best.key != .undetermined, best.value >= 0.5, sentence.count >= 12 {
                    return LanguageGuess(code: best.key.rawValue, probability: best.value)
                }
                return fallback.map { code in
                    LanguageGuess(code: code, probability: hypotheses[NLLanguage(rawValue: code)] ?? 0)
                }
            }
        }

        // MARK: - Sentiment

        /// Scores each sentence on its own, treating it as a paragraph, which
        /// is the unit NaturalLanguage's sentiment model is documented for.
        private static func scoreSentiment(of sentences: [String]) -> [Double?] {
            let tagger = NLTagger(tagSchemes: [.sentimentScore])
            return sentences.map { sentence in
                guard !sentence.isEmpty else { return nil }
                tagger.string = sentence
                let (tag, _) = tagger.tag(at: sentence.startIndex, unit: .paragraph, scheme: .sentimentScore)
                return tag.flatMap { Double($0.rawValue) }.map { min(max($0, -1), 1) }
            }
        }

        // MARK: - Words

        private static func tagWords(of text: String) -> (words: [WordReading], entities: [EntityReading]) {
            let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass, .lemma])
            tagger.string = text
            let whole = text.startIndex..<text.endIndex

            var entities: [EntityReading] = []
            let nameOptions: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
            tagger.enumerateTags(in: whole, unit: .word, scheme: .nameType, options: nameOptions) { tag, range in
                if let tag, let kind = EntityKind(tag: tag) {
                    entities.append(EntityReading(span: span(of: range, in: text), text: String(text[range]), kind: kind))
                }
                return true
            }

            let wordOptions: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther]
            var lemmas: [Int: String] = [:]
            tagger.enumerateTags(in: whole, unit: .word, scheme: .lemma, options: wordOptions) { tag, range in
                if let tag {
                    lemmas[span(of: range, in: text).lowerBound] = tag.rawValue
                }
                return true
            }

            var words: [WordReading] = []
            tagger.enumerateTags(in: whole, unit: .word, scheme: .lexicalClass, options: wordOptions) { tag, range in
                let wordSpan = span(of: range, in: text)
                let word = String(text[range])
                words.append(WordReading(
                    span: wordSpan,
                    text: word,
                    partOfSpeech: tag.map { PartOfSpeech(tag: $0) },
                    lemma: lemmas[wordSpan.lowerBound],
                    syllables: SyllableCounter.english.syllables(in: word)
                ))
                return true
            }
            return (words, entities)
        }

        /// Groups mentions of the same name, most mentioned first. For people,
        /// a single name that is part of a longer one ("Delgado" in "Maria
        /// Delgado") joins it.
        private static func groupEntities(_ entities: [EntityReading]) -> [EntityGroup] {
            EntityKind.allCases.compactMap { kind in
                var order: [String] = []
                var names: [String: String] = [:]
                var spans: [String: [TextSpan]] = [:]
                for mention in entities where mention.kind == kind {
                    let key = mention.text.lowercased()
                    if spans[key] == nil {
                        order.append(key)
                        names[key] = mention.text
                    }
                    spans[key, default: []].append(mention.span)
                }
                guard !order.isEmpty else { return nil }

                if kind == .person {
                    for key in order where !key.contains(" ") {
                        let fullName = order.first { other in
                            other != key && other.split(separator: " ").contains { $0 == key }
                        }
                        if let fullName, let mentions = spans[key] {
                            spans[fullName, default: []] += mentions
                            spans[key] = nil
                        }
                    }
                    order.removeAll { spans[$0] == nil }
                }

                let clusters = order.map { key in
                    EntityCluster(
                        name: names[key] ?? key,
                        kind: kind,
                        spans: (spans[key] ?? []).sorted { $0.lowerBound < $1.lowerBound }
                    )
                }
                // Most mentioned first; ties keep the order of first mention.
                let ranked = clusters.indices.sorted { first, second in
                    let firstCount = clusters[first].spans.count
                    let secondCount = clusters[second].spans.count
                    return firstCount != secondCount ? firstCount > secondCount : first < second
                }
                return EntityGroup(kind: kind, clusters: ranked.map { clusters[$0] })
            }
        }

        private static func shares(of words: [WordReading]) -> [PartOfSpeechShare] {
            let tagged = words.compactMap(\.partOfSpeech)
            guard !tagged.isEmpty else { return [] }
            var counts: [PartOfSpeech: Int] = [:]
            for partOfSpeech in tagged {
                counts[partOfSpeech, default: 0] += 1
            }
            return PartOfSpeech.allCases.compactMap { partOfSpeech in
                guard let count = counts[partOfSpeech] else { return nil }
                return PartOfSpeechShare(partOfSpeech: partOfSpeech, count: count, share: Double(count) / Double(tagged.count))
            }
        }

        /// Words whose lemma differs from their spelling, most frequent first.
        private static func lemmaPairs(of words: [WordReading]) -> [LemmaPair] {
            var order: [String] = []
            var lemmas: [String: String] = [:]
            var counts: [String: Int] = [:]
            for word in words {
                guard let lemma = word.lemma?.lowercased(), !lemma.isEmpty else { continue }
                let surface = word.text.lowercased()
                guard surface != lemma, surface.count > 1, !surface.contains("'"), !surface.contains("\u{2019}") else { continue }
                if counts[surface] == nil {
                    order.append(surface)
                    lemmas[surface] = lemma
                }
                counts[surface, default: 0] += 1
            }
            return order.enumerated()
                .sorted { (counts[$0.1] ?? 0, -$0.0) > (counts[$1.1] ?? 0, -$1.0) }
                .map { LemmaPair(word: $0.1, lemma: lemmas[$0.1] ?? $0.1, count: counts[$0.1] ?? 0) }
        }

        /// Converts a range of `text` into UTF-16 offsets.
        static func span(of range: Range<String.Index>, in text: String) -> TextSpan {
            let converted = NSRange(range, in: text)
            return converted.location..<(converted.location + converted.length)
        }
    }
}

extension LanguageLab.EntityKind {
    init?(tag: NLTag) {
        switch tag {
        case .personalName: self = .person
        case .placeName: self = .place
        case .organizationName: self = .organization
        default: return nil
        }
    }
}

extension LanguageLab.PartOfSpeech {
    init(tag: NLTag) {
        switch tag {
        case .noun: self = .noun
        case .verb: self = .verb
        case .adjective: self = .adjective
        case .adverb: self = .adverb
        case .pronoun: self = .pronoun
        case .number: self = .number
        case .determiner, .preposition, .conjunction, .particle, .classifier: self = .function
        default: self = .other
        }
    }
}
