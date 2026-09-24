import Foundation

/// How hard a text is to read, scored by six classic readability formulas,
/// together with the counts they are built from.
///
/// Every formula weighs how long the sentences are against how long the
/// words are, measured in syllables (Flesch, Flesch–Kincaid, Gunning Fog,
/// SMOG) or in letters (Coleman–Liau, ARI). They were calibrated on English
/// school texts, so they are meaningful for English prose only.
///
///     let report = ReadabilityReport(text: essay)
///     report.fleschReadingEase        // 64.2
///     report.readingEase.label        // "Plain English"
///     report.consensusGrade           // 8.7
public struct ReadabilityReport: Hashable, Sendable {
    /// Each sentence with its own counts.
    public let sentences: [SentenceReadability]
    /// Words, numbers included.
    public let wordCount: Int
    public let syllableCount: Int
    /// Letters and digits inside words.
    public let letterCount: Int
    /// Every character of the text, spaces and punctuation included.
    public let characterCount: Int
    /// Words of three or more syllables, which SMOG counts.
    public let polysyllableCount: Int
    /// Gunning's "complex words": three or more syllables without counting
    /// the endings -es, -ed and -ing, leaving out proper nouns and
    /// hyphenated compounds.
    public let complexWordCount: Int
    /// The words of three or more syllables, in order.
    public let polysyllabicWords: [ProseWord]
    /// Vocabulary richness of the text's words.
    public let diversity: LexicalDiversity

    /// Average adult silent reading speed for English non-fiction, from
    /// Brysbaert's 2019 meta-analysis of 190 studies.
    public static let wordsPerMinute: Double = 238

    public init(text: String, syllableCounter: SyllableCounter = .english) {
        var sentences: [SentenceReadability] = []
        var words = 0
        var syllables = 0
        var letters = 0
        var polysyllables = 0
        var complexWords = 0
        var polysyllabicWords: [ProseWord] = []
        var vocabulary: [String] = []

        for sentence in ProseTokenizer.sentences(in: text) {
            let sentenceWords = ProseTokenizer.words(in: text, within: sentence.range)
            var sentenceSyllables = 0
            var sentencePolysyllables = 0
            for (position, word) in sentenceWords.enumerated() {
                let count = syllableCounter.syllables(in: word.text)
                sentenceSyllables += count
                letters += word.text.reduce(0) { $0 + ($1.isLetter || $1.isNumber ? 1 : 0) }
                guard !word.isNumeric else { continue }
                vocabulary.append(word.normalized)
                if count >= 3 {
                    sentencePolysyllables += 1
                    polysyllabicWords.append(word)
                }
                if Self.isComplex(word, syllables: count, opensSentence: position == 0, counter: syllableCounter) {
                    complexWords += 1
                }
            }
            words += sentenceWords.count
            syllables += sentenceSyllables
            polysyllables += sentencePolysyllables
            sentences.append(SentenceReadability(
                text: sentence.text,
                range: sentence.range,
                wordCount: sentenceWords.count,
                syllableCount: sentenceSyllables,
                polysyllableCount: sentencePolysyllables
            ))
        }

        self.sentences = sentences
        self.wordCount = words
        self.syllableCount = syllables
        self.letterCount = letters
        self.characterCount = text.count
        self.polysyllableCount = polysyllables
        self.complexWordCount = complexWords
        self.polysyllabicWords = polysyllabicWords
        self.diversity = LexicalDiversity(words: vocabulary)
    }

    // MARK: - Counts and averages

    public var sentenceCount: Int { sentences.count }

    /// True when the text has no words; every score is then 0.
    public var isEmpty: Bool { wordCount == 0 }

    /// Words per sentence.
    public var averageSentenceLength: Double {
        sentenceCount == 0 ? 0 : Double(wordCount) / Double(sentenceCount)
    }

    /// Letters per word.
    public var averageWordLength: Double {
        wordCount == 0 ? 0 : Double(letterCount) / Double(wordCount)
    }

    public var averageSyllablesPerWord: Double {
        wordCount == 0 ? 0 : Double(syllableCount) / Double(wordCount)
    }

    /// How long a typical adult takes to read the text silently, in seconds.
    public var readingTime: TimeInterval {
        Double(wordCount) / Self.wordsPerMinute * 60
    }

    // MARK: - Formulas

    /// Flesch Reading Ease (1948): higher is easier. Plain English scores
    /// 60–70; most academic writing scores below 30.
    public var fleschReadingEase: Double {
        guard !isEmpty else { return 0 }
        return 206.835 - 1.015 * averageSentenceLength - 84.6 * averageSyllablesPerWord
    }

    /// Flesch–Kincaid Grade Level (1975): the US school grade that can read
    /// the text.
    public var fleschKincaidGrade: Double {
        guard !isEmpty else { return 0 }
        return 0.39 * averageSentenceLength + 11.8 * averageSyllablesPerWord - 15.59
    }

    /// Gunning Fog Index (1952): years of schooling needed on a first
    /// reading.
    public var gunningFog: Double {
        guard !isEmpty else { return 0 }
        return 0.4 * (averageSentenceLength + 100 * Double(complexWordCount) / Double(wordCount))
    }

    /// SMOG Grade (McLaughlin, 1969), scaled from its 30-sentence sample to
    /// the text's length.
    public var smogIndex: Double {
        guard !isEmpty else { return 0 }
        return 1.0430 * (Double(polysyllableCount) * 30 / Double(sentenceCount)).squareRoot() + 3.1291
    }

    /// Coleman–Liau Index (1975): a grade level from letters per 100 words
    /// and sentences per 100 words, with no syllables involved.
    public var colemanLiauIndex: Double {
        guard !isEmpty else { return 0 }
        let lettersPer100 = Double(letterCount) / Double(wordCount) * 100
        let sentencesPer100 = Double(sentenceCount) / Double(wordCount) * 100
        return 0.0588 * lettersPer100 - 0.296 * sentencesPer100 - 15.8
    }

    /// Automated Readability Index (1967): a grade level from characters per
    /// word and words per sentence.
    public var automatedReadabilityIndex: Double {
        guard !isEmpty else { return 0 }
        return 4.71 * averageWordLength + 0.5 * averageSentenceLength - 21.43
    }

    /// The mean of the five grade-level formulas, which disagree in
    /// different directions and so balance each other out.
    public var consensusGrade: Double {
        let grades = ReadabilityFormula.allCases.filter(\.isGradeLevel).map { score($0) }
        return grades.reduce(0, +) / Double(grades.count)
    }

    /// Where the Flesch Reading Ease score falls on Flesch's own scale.
    public var readingEase: ReadingEase {
        ReadingEase(score: fleschReadingEase)
    }

    /// The score of one formula.
    public func score(_ formula: ReadabilityFormula) -> Double {
        switch formula {
        case .fleschReadingEase: fleschReadingEase
        case .fleschKincaidGrade: fleschKincaidGrade
        case .gunningFog: gunningFog
        case .smog: smogIndex
        case .colemanLiau: colemanLiauIndex
        case .automatedReadabilityIndex: automatedReadabilityIndex
        }
    }

    static func isComplex(_ word: ProseWord, syllables: Int, opensSentence: Bool, counter: SyllableCounter) -> Bool {
        guard syllables >= 3, !word.isHyphenated else { return false }
        if word.isCapitalized && !opensSentence { return false }
        let lowercase = word.normalized
        for ending in ["ing", "ed", "es"] where lowercase.hasSuffix(ending) && lowercase.count > ending.count + 2 {
            return counter.syllables(in: String(lowercase.dropLast(ending.count))) >= 3
        }
        return true
    }
}

/// One sentence's counts, and its difficulty on its own.
public struct SentenceReadability: Hashable, Sendable {
    public let text: String
    /// Where the sentence sits in the text the report was made from.
    public let range: Range<String.Index>
    public let wordCount: Int
    public let syllableCount: Int
    public let polysyllableCount: Int

    /// The Flesch–Kincaid grade of this sentence alone: long sentences of
    /// long words score high.
    public var gradeLevel: Double {
        guard wordCount > 0 else { return 0 }
        return 0.39 * Double(wordCount) + 11.8 * Double(syllableCount) / Double(wordCount) - 15.59
    }
}

/// The readability formulas `ReadabilityReport` computes.
public enum ReadabilityFormula: String, CaseIterable, Sendable {
    case fleschReadingEase
    case fleschKincaidGrade
    case gunningFog
    case smog
    case colemanLiau
    case automatedReadabilityIndex

    public var name: String {
        switch self {
        case .fleschReadingEase: "Flesch Reading Ease"
        case .fleschKincaidGrade: "Flesch–Kincaid Grade"
        case .gunningFog: "Gunning Fog"
        case .smog: "SMOG"
        case .colemanLiau: "Coleman–Liau"
        case .automatedReadabilityIndex: "Automated Readability"
        }
    }

    /// True for the formulas that estimate a US school grade; Flesch Reading
    /// Ease is a 0–100 score instead.
    public var isGradeLevel: Bool {
        self != .fleschReadingEase
    }
}

/// Flesch's scale for Reading Ease scores.
public enum ReadingEase: Int, CaseIterable, Comparable, Sendable {
    case veryEasy, easy, fairlyEasy, plainEnglish, fairlyDifficult, difficult, veryDifficult, extremelyDifficult

    public init(score: Double) {
        switch score {
        case 90...: self = .veryEasy
        case 80..<90: self = .easy
        case 70..<80: self = .fairlyEasy
        case 60..<70: self = .plainEnglish
        case 50..<60: self = .fairlyDifficult
        case 30..<50: self = .difficult
        case 10..<30: self = .veryDifficult
        default: self = .extremelyDifficult
        }
    }

    public var label: String {
        switch self {
        case .veryEasy: "Very easy"
        case .easy: "Easy"
        case .fairlyEasy: "Fairly easy"
        case .plainEnglish: "Plain English"
        case .fairlyDifficult: "Fairly difficult"
        case .difficult: "Difficult"
        case .veryDifficult: "Very difficult"
        case .extremelyDifficult: "Extremely difficult"
        }
    }

    /// Who can read text at this level, in Flesch's terms.
    public var typicalReader: String {
        switch self {
        case .veryEasy: "5th grade"
        case .easy: "6th grade"
        case .fairlyEasy: "7th grade"
        case .plainEnglish: "8th–9th grade"
        case .fairlyDifficult: "10th–12th grade"
        case .difficult: "College"
        case .veryDifficult: "College graduate"
        case .extremelyDifficult: "Professional"
        }
    }

    public static func < (lhs: ReadingEase, rhs: ReadingEase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
