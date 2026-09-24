import XCTest
@testable import ProseKit

final class SimilarityMatrixTests: XCTestCase {
    func testCosineMatrix() {
        let matrix = SimilarityMatrix(cosineOf: [[1, 0], [0, 1], [1, 1], [0, 0]])
        XCTAssertEqual(matrix.size, 4)
        XCTAssertEqual(matrix[0, 1], 0, accuracy: 1e-12)
        XCTAssertEqual(matrix[0, 2], 1 / 2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(matrix[3, 0], 0, "A zero vector is similar to nothing")
        for index in 0..<4 {
            XCTAssertEqual(matrix[index, index], 1, "The diagonal is always 1")
        }
        for row in 0..<4 {
            for column in 0..<4 {
                XCTAssertEqual(matrix[row, column], matrix[column, row], "Symmetric")
            }
        }
    }

    func testLexicalSimilarityFollowsSharedWords() throws {
        let matrix = SimilarityMatrix.lexical(sentences: [
            "The new satellite launched today.",
            "Satellites like this one launch often.",
            "I would like some soup.",
            "The new satellite launched today!",
        ])
        XCTAssertGreaterThan(matrix[0, 1], 0.1, "\"satellite\" and \"satellites\" share a stem")
        XCTAssertEqual(matrix[0, 2], 0, accuracy: 1e-12, "Only stopwords in common")
        XCTAssertEqual(matrix[0, 3], 1, accuracy: 1e-9, "Same words, same vector")

        let pair = try XCTUnwrap(matrix.mostSimilarPair())
        XCTAssertEqual([pair.first, pair.second], [0, 3])
        XCTAssertEqual(pair.similarity, 1, accuracy: 1e-9)
        XCTAssertEqual(matrix.offDiagonalRange?.lowerBound ?? -1, 0, accuracy: 1e-12)

        let amongFirstThree = try XCTUnwrap(matrix.mostSimilarPair(amongFirst: 3))
        XCTAssertEqual([amongFirstThree.first, amongFirstThree.second], [0, 1])
        XCTAssertNil(matrix.mostSimilarPair(amongFirst: 1))
    }

    func testRareWordsWeighMoreThanCommonOnes() {
        // Every document says "report"; only two share "volcano".
        let matrix = SimilarityMatrix.lexical(documents: [
            ["report", "volcano"],
            ["report", "volcano"],
            ["report", "harbor"],
        ])
        XCTAssertEqual(matrix[0, 1], 1, accuracy: 1e-9)
        XCTAssertLessThan(matrix[0, 2], 0.5)
        XCTAssertGreaterThan(matrix[0, 2], 0)
    }

    func testDegenerateSizes() {
        XCTAssertEqual(SimilarityMatrix.lexical(sentences: []).size, 0)
        XCTAssertNil(SimilarityMatrix.lexical(sentences: []).mostSimilarPair())
        let single = SimilarityMatrix.lexical(sentences: ["Only one sentence."])
        XCTAssertEqual(single[0, 0], 1)
        XCTAssertNil(single.mostSimilarPair())
        XCTAssertNil(single.offDiagonalRange)
    }

    func testLightStemming() {
        XCTAssertEqual(SimilarityMatrix.lightStem("cities"), "city")
        XCTAssertEqual(SimilarityMatrix.lightStem("satellites"), "satellite")
        XCTAssertEqual(SimilarityMatrix.lightStem("glass"), "glass")
        XCTAssertEqual(SimilarityMatrix.lightStem("virus"), "virus")
        XCTAssertEqual(SimilarityMatrix.lightStem("analysis"), "analysis")
    }

    // MARK: - Embedding math

    func testVectorBasics() {
        XCTAssertEqual(EmbeddingMath.dot([1, 2, 3], [4, 5, 6]), 32)
        XCTAssertEqual(EmbeddingMath.length([3, 4]), 5)
        XCTAssertEqual(EmbeddingMath.length(EmbeddingMath.normalized([3, 4, 12])), 1, accuracy: 1e-12)
        XCTAssertEqual(EmbeddingMath.normalized([0, 0]), [0, 0])
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 1], [2, 2]), 1, accuracy: 1e-12)
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 0], [0, 3]), 0, accuracy: 1e-12)
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 2], [-1, -2]), -1, accuracy: 1e-12)
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 2], [1, 2, 3]), 0, "Mismatched lengths")
        XCTAssertEqual(EmbeddingMath.analogy([1], minus: [1, 2], plus: [1]), [])
    }

    /// A toy space whose axes mean "royal", "male" and "female".
    func testAnalogyArithmeticFindsQueen() throws {
        let vocabulary: [String: [Double]] = [
            "king": [0.9, 0.8, 0.1],
            "queen": [0.9, 0.1, 0.8],
            "man": [0.1, 0.9, 0.1],
            "woman": [0.1, 0.1, 0.9],
            "apple": [0.2, 0.3, 0.3],
            "prince": [0.7, 0.7, 0.1],
        ]
        let target = EmbeddingMath.analogy(
            try XCTUnwrap(vocabulary["king"]),
            minus: try XCTUnwrap(vocabulary["man"]),
            plus: try XCTUnwrap(vocabulary["woman"])
        )
        let best = vocabulary
            .filter { !["king", "man", "woman"].contains($0.key) }
            .max { EmbeddingMath.cosineSimilarity($0.value, target) < EmbeddingMath.cosineSimilarity($1.value, target) }
        XCTAssertEqual(best?.key, "queen")
    }
}
