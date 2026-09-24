import Foundation

/// A key phrase found by `KeywordExtractor`.
public struct RankedKeyphrase: Hashable, Sendable {
    /// The phrase as first written, such as "European Space Agency".
    public let text: String
    /// The phrase's words in lowercase, which identify it.
    public let words: [String]
    /// The RAKE score: the sum of its words' degree-to-frequency ratios.
    public let score: Double
    /// Everywhere the phrase occurs, in order.
    public let occurrences: [Range<String.Index>]

    /// The phrase in lowercase.
    public var normalized: String {
        words.joined(separator: " ")
    }

    /// How many times the phrase occurs.
    public var frequency: Int {
        occurrences.count
    }
}

/// Finds a text's key phrases with RAKE, Rapid Automatic Keyword Extraction
/// (Rose, Engel, Cramer & Cowley, 2010).
///
/// RAKE needs no training and no dictionary beyond a stopword list. It
/// splits the text at stopwords and punctuation, which leaves candidate
/// phrases such as "linear diophantine equations". Every word then scores
/// its *degree* (the total length of the candidates it appears in) divided
/// by its *frequency* (how many candidates it appears in). Words that turn up
/// inside long phrases outscore words that mostly stand alone, and a phrase
/// scores the sum of its words.
///
///     let phrases = KeywordExtractor().keyphrases(in: abstract)
///     phrases.first?.text   // "minimal generating sets"
public struct KeywordExtractor: Sendable {
    /// Words that separate phrases, in lowercase with straight apostrophes.
    public var stopwords: Set<String>
    /// Candidates with more words than this are dropped before scoring,
    /// which stops long runs of names and titles from dominating.
    public var maximumPhraseLength: Int
    /// Shorter words act as separators too.
    public var minimumWordLength: Int
    /// Whether to add RAKE's "adjoining keywords": two key phrases joined by
    /// one or two stopwords, such as "axis of evil", when that exact
    /// combination occurs at least twice.
    public var joinsAdjoiningKeywords: Bool

    public init(
        stopwords: Set<String> = ProseStopwords.english,
        maximumPhraseLength: Int = 4,
        minimumWordLength: Int = 2,
        joinsAdjoiningKeywords: Bool = true
    ) {
        self.stopwords = stopwords
        self.maximumPhraseLength = maximumPhraseLength
        self.minimumWordLength = minimumWordLength
        self.joinsAdjoiningKeywords = joinsAdjoiningKeywords
    }

    /// Every key phrase in `text`, best first. Ties go to the more frequent
    /// phrase, then to the one that appears first.
    public func keyphrases(in text: String) -> [RankedKeyphrase] {
        let words = ProseTokenizer.words(in: text)
        let split = splitIntoCandidates(words, of: text)
        let kept = Set(split.candidates.indices.filter { split.candidates[$0].words.count <= maximumPhraseLength })

        // Word scores: degree over frequency, across the candidates kept.
        var frequency: [String: Double] = [:]
        var degree: [String: Double] = [:]
        for index in kept {
            let phraseWords = split.candidates[index].words
            for word in phraseWords {
                frequency[word, default: 0] += 1
                degree[word, default: 0] += Double(phraseWords.count)
            }
        }
        func score(ofCandidate index: Int) -> Double {
            split.candidates[index].words.reduce(0) { total, word in
                total + (degree[word] ?? 0) / (frequency[word] ?? 1)
            }
        }

        var phrases: [[String]: Accumulator] = [:]
        for index in kept.sorted() {
            let candidate = split.candidates[index]
            let range = words[candidate.firstWord].range.lowerBound..<words[candidate.lastWord].range.upperBound
            if phrases[candidate.words] == nil {
                let display = words[candidate.firstWord...candidate.lastWord].map(\.text).joined(separator: " ")
                phrases[candidate.words] = Accumulator(text: display, score: score(ofCandidate: index))
            }
            phrases[candidate.words]?.occurrences.append(range)
        }

        if joinsAdjoiningKeywords {
            for adjoined in adjoiningKeywords(in: split, kept: kept, words: words, text: text)
            where phrases[adjoined.words] == nil {
                phrases[adjoined.words] = Accumulator(
                    text: adjoined.text,
                    score: score(ofCandidate: adjoined.first) + score(ofCandidate: adjoined.second),
                    occurrences: adjoined.occurrences
                )
            }
        }

        return phrases
            .map { phraseWords, phrase in
                RankedKeyphrase(text: phrase.text, words: phraseWords, score: phrase.score, occurrences: phrase.occurrences)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
                return lhs.occurrences[0].lowerBound < rhs.occurrences[0].lowerBound
            }
    }

    // MARK: - Candidates

    private struct Candidate {
        var firstWord: Int
        var lastWord: Int
        var words: [String]
    }

    /// Within a stretch of text between punctuation marks: candidates
    /// (by index) and the stopwords between them.
    private enum Element {
        case candidate(Int)
        case stopword(String)
    }

    private struct Accumulator {
        var text: String
        var score: Double
        var occurrences: [Range<String.Index>] = []
    }

    private func splitIntoCandidates(_ words: [ProseWord], of text: String) -> (candidates: [Candidate], stretches: [[Element]]) {
        var candidates: [Candidate] = []
        var stretches: [[Element]] = [[]]
        var run: [Int] = []
        var runWords: [String] = []

        func closeRun() {
            guard let first = run.first, let last = run.last else { return }
            candidates.append(Candidate(firstWord: first, lastWord: last, words: runWords))
            stretches[stretches.count - 1].append(.candidate(candidates.count - 1))
            run = []
            runWords = []
        }

        for (index, word) in words.enumerated() {
            if index > 0 {
                let gap = text[words[index - 1].range.upperBound..<word.range.lowerBound]
                // Punctuation and line breaks end a phrase; plain spaces don't.
                if gap.contains(where: { !$0.isWhitespace || $0.isNewline }) {
                    closeRun()
                    stretches.append([])
                }
            }
            let key = Self.key(for: word)
            if isSeparator(key, word) {
                closeRun()
                stretches[stretches.count - 1].append(.stopword(key))
            } else {
                run.append(index)
                runWords.append(key)
            }
        }
        closeRun()
        return (candidates, stretches)
    }

    private func isSeparator(_ key: String, _ word: ProseWord) -> Bool {
        if word.isNumeric || stopwords.contains(key) || stopwords.contains(word.normalized) { return true }
        return key.filter(\.isLetter).count < minimumWordLength
    }

    /// Lowercase, straight apostrophes, and no possessive: "Agency's" is
    /// "agency".
    static func key(for word: ProseWord) -> String {
        let normalized = word.normalized
        if normalized.hasSuffix("'s") { return String(normalized.dropLast(2)) }
        if normalized.hasSuffix("'") { return String(normalized.dropLast()) }
        return normalized
    }

    // MARK: - Adjoining keywords

    private struct AdjoinedPhrase {
        var words: [String]
        var text: String
        var first: Int
        var second: Int
        var occurrences: [Range<String.Index>]
    }

    /// Pairs of kept candidates separated by one or two stopwords, keeping
    /// only the combinations that occur at least twice.
    private func adjoiningKeywords(
        in split: (candidates: [Candidate], stretches: [[Element]]),
        kept: Set<Int>,
        words: [ProseWord],
        text: String
    ) -> [AdjoinedPhrase] {
        var found: [[String]: AdjoinedPhrase] = [:]
        var order: [[String]] = []

        for stretch in split.stretches {
            for (position, element) in stretch.enumerated() {
                guard case .candidate(let first) = element, kept.contains(first) else { continue }
                var next = position + 1
                var interior: [String] = []
                while next < stretch.count, case .stopword(let stopword) = stretch[next] {
                    interior.append(stopword)
                    next += 1
                }
                guard (1...2).contains(interior.count), next < stretch.count,
                      case .candidate(let second) = stretch[next], kept.contains(second) else { continue }

                let firstCandidate = split.candidates[first]
                let secondCandidate = split.candidates[second]
                let key = firstCandidate.words + interior + secondCandidate.words
                let range = words[firstCandidate.firstWord].range.lowerBound..<words[secondCandidate.lastWord].range.upperBound
                if found[key] == nil {
                    let display = words[firstCandidate.firstWord...secondCandidate.lastWord].map(\.text).joined(separator: " ")
                    found[key] = AdjoinedPhrase(words: key, text: display, first: first, second: second, occurrences: [])
                    order.append(key)
                }
                found[key]?.occurrences.append(range)
            }
        }
        return order.compactMap { found[$0] }.filter { $0.occurrences.count >= 2 }
    }
}
