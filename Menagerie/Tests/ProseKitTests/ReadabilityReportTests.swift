import XCTest
@testable import ProseKit

final class ReadabilityReportTests: XCTestCase {
    /// Six one-syllable words in one sentence, so every formula can be
    /// checked by hand.
    func testFormulasOnAHandCountedSentence() {
        let report = ReadabilityReport(text: "The cat sat on the mat.")
        XCTAssertEqual(report.wordCount, 6)
        XCTAssertEqual(report.sentenceCount, 1)
        XCTAssertEqual(report.syllableCount, 6)
        XCTAssertEqual(report.letterCount, 17)
        XCTAssertEqual(report.polysyllableCount, 0)

        XCTAssertEqual(report.fleschReadingEase, 206.835 - 1.015 * 6 - 84.6, accuracy: 1e-9)
        XCTAssertEqual(report.fleschKincaidGrade, 0.39 * 6 + 11.8 - 15.59, accuracy: 1e-9)
        XCTAssertEqual(report.gunningFog, 0.4 * 6, accuracy: 1e-9)
        XCTAssertEqual(report.smogIndex, 3.1291, accuracy: 1e-9)
        XCTAssertEqual(report.colemanLiauIndex, 0.0588 * (17.0 / 6 * 100) - 0.296 * (1.0 / 6 * 100) - 15.8, accuracy: 1e-9)
        XCTAssertEqual(report.automatedReadabilityIndex, 4.71 * 17.0 / 6 + 0.5 * 6 - 21.43, accuracy: 1e-9)
    }

    func testAveragesAcrossSentences() {
        // 3 + 4 words, 1 + 1 + 1 + 1 + 1 + 1 + 1 syllables, 2 sentences.
        let report = ReadabilityReport(text: "I like cats. Dogs are fine too.")
        XCTAssertEqual(report.averageSentenceLength, 3.5, accuracy: 1e-9)
        XCTAssertEqual(report.averageSyllablesPerWord, 1, accuracy: 1e-9)
        XCTAssertEqual(report.fleschReadingEase, 206.835 - 1.015 * 3.5 - 84.6, accuracy: 1e-9)
        XCTAssertEqual(report.sentences.map(\.wordCount), [3, 4])
    }

    func testChildrensTextScoresFarEasierThanAcademicText() {
        let children = ReadabilityReport(text: "The cat sat on the mat. The dog ran to the sun. We had fun. It was a good day.")
        let academic = ReadabilityReport(text: """
            The epistemological ramifications of poststructuralist hermeneutics necessitate a \
            comprehensive reevaluation of methodological presuppositions underlying contemporary \
            sociolinguistic investigations of institutional communication.
            """)

        XCTAssertGreaterThan(children.fleschReadingEase, 100)
        XCTAssertLessThan(academic.fleschReadingEase, 0)
        XCTAssertLessThan(children.fleschKincaidGrade, 1)
        XCTAssertGreaterThan(academic.fleschKincaidGrade, 20)
        XCTAssertEqual(children.readingEase, .veryEasy)
        XCTAssertEqual(academic.readingEase, .extremelyDifficult)

        // Every formula agrees on the order.
        for formula in ReadabilityFormula.allCases {
            if formula.isGradeLevel {
                XCTAssertLessThan(children.score(formula), academic.score(formula) - 10, formula.name)
            } else {
                XCTAssertGreaterThan(children.score(formula), academic.score(formula) + 100, formula.name)
            }
        }
        XCTAssertLessThan(children.consensusGrade, 2)
        XCTAssertGreaterThan(academic.consensusGrade, 18)
    }

    func testEverydayProseLandsInTheMiddle() {
        let report = ReadabilityReport(text: """
            The city council voted on Tuesday to expand the bus network next year. Officials said \
            the new routes would connect three neighborhoods that currently have no direct service. \
            Riders welcomed the plan, although some worried about higher fares.
            """)
        XCTAssertGreaterThan(report.fleschReadingEase, 40)
        XCTAssertLessThan(report.fleschReadingEase, 80)
        XCTAssertGreaterThan(report.consensusGrade, 5)
        XCTAssertLessThan(report.consensusGrade, 14)
    }

    func testComplexWordsFollowGunning() {
        // "communication" and "beautiful" count. "Jennifer" is a proper noun,
        // "well-organized" is hyphenated, and "created" only reaches three
        // syllables through -ed.
        let report = ReadabilityReport(text: "Communication is beautiful and Jennifer created well-organized plans.")
        XCTAssertEqual(report.complexWordCount, 2)
        XCTAssertEqual(report.polysyllabicWords.map(\.text), ["Communication", "beautiful", "Jennifer", "created", "well-organized"])
        XCTAssertEqual(report.polysyllableCount, 5)
    }

    func testSentenceGradesRankHardSentencesHigher() {
        let report = ReadabilityReport(text: """
            I ran. Notwithstanding considerable institutional opposition, the administration \
            implemented comprehensive environmental regulations affecting manufacturing facilities.
            """)
        XCTAssertEqual(report.sentences.count, 2)
        XCTAssertLessThan(report.sentences[0].gradeLevel, 0)
        XCTAssertGreaterThan(report.sentences[1].gradeLevel, 20)
    }

    func testNumbersCountTheirSpokenSyllables() {
        // "It (1) was (1) nineteen eighty-four (5)."
        let report = ReadabilityReport(text: "It was 1984.")
        XCTAssertEqual(report.syllableCount, 7)
        XCTAssertEqual(report.polysyllableCount, 0, "Numbers are never counted as hard words")
    }

    func testReadingTime() {
        let text = Array(repeating: "word", count: 238).joined(separator: " ")
        XCTAssertEqual(ReadabilityReport(text: text).readingTime, 60, accuracy: 1e-9)
    }

    func testReadingEaseBands() {
        XCTAssertEqual(ReadingEase(score: 120), .veryEasy)
        XCTAssertEqual(ReadingEase(score: 85), .easy)
        XCTAssertEqual(ReadingEase(score: 65), .plainEnglish)
        XCTAssertEqual(ReadingEase(score: 45), .difficult)
        XCTAssertEqual(ReadingEase(score: 5), .extremelyDifficult)
        XCTAssertEqual(ReadingEase(score: -40), .extremelyDifficult)
        XCTAssertLessThan(ReadingEase.veryEasy, ReadingEase.difficult)
        XCTAssertEqual(ReadingEase.plainEnglish.typicalReader, "8th–9th grade")
    }

    func testEmptyText() {
        for text in ["", "   \n ", "— … —"] {
            let report = ReadabilityReport(text: text)
            XCTAssertTrue(report.isEmpty)
            XCTAssertEqual(report.wordCount, 0)
            XCTAssertEqual(report.sentenceCount, 0)
            XCTAssertEqual(report.readingTime, 0)
            XCTAssertNil(report.diversity.mtld)
            for formula in ReadabilityFormula.allCases {
                XCTAssertEqual(report.score(formula), 0, formula.name)
            }
            XCTAssertEqual(report.consensusGrade, 0)
        }
    }

    func testSingleWord() {
        let report = ReadabilityReport(text: "Hello")
        XCTAssertFalse(report.isEmpty)
        XCTAssertEqual(report.wordCount, 1)
        XCTAssertEqual(report.sentenceCount, 1)
        XCTAssertEqual(report.syllableCount, 2)
        XCTAssertEqual(report.fleschReadingEase, 206.835 - 1.015 - 84.6 * 2, accuracy: 1e-9)
        for formula in ReadabilityFormula.allCases {
            XCTAssertTrue(report.score(formula).isFinite, formula.name)
        }
        XCTAssertEqual(report.diversity.typeTokenRatio, 1)
    }
}
