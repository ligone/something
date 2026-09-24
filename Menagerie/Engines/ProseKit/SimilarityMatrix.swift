import Foundation

/// Pairwise similarities between the items of a list, such as the sentences
/// of a text, for drawing as a heatmap.
///
/// Scores are cosine similarities. The diagonal, each item compared with
/// itself, is always 1.
public struct SimilarityMatrix: Hashable, Sendable {
    /// The number of items; the matrix is `size` × `size`.
    public let size: Int
    /// Row-major scores.
    public let values: [Double]

    /// Wraps precomputed scores. `values` must hold `size * size` numbers.
    public init(size: Int, values: [Double]) {
        precondition(values.count == size * size, "A \(size)×\(size) matrix needs \(size * size) values")
        self.size = size
        self.values = values
    }

    public subscript(row: Int, column: Int) -> Double {
        values[row * size + column]
    }

    /// Cosine similarity between every pair of vectors. An empty or zero
    /// vector scores 0 against everything else.
    public init(cosineOf vectors: [[Double]]) {
        let unit = vectors.map(EmbeddingMath.normalized)
        let size = vectors.count
        var values = [Double](repeating: 0, count: size * size)
        for row in 0..<size {
            values[row * size + row] = 1
            for column in (row + 1)..<size {
                let score = EmbeddingMath.dot(unit[row], unit[column])
                values[row * size + column] = score
                values[column * size + row] = score
            }
        }
        self.init(size: size, values: values)
    }

    /// Word-overlap similarity: the cosine between TF–IDF vectors, where each
    /// word counts its occurrences in a document, weighted up when few other
    /// documents use it.
    ///
    /// - Parameter documents: each document's words, already normalized.
    public static func lexical(documents: [[String]]) -> SimilarityMatrix {
        var documentFrequency: [String: Int] = [:]
        for document in documents {
            for term in Set(document) {
                documentFrequency[term, default: 0] += 1
            }
        }
        // Smoothed inverse document frequency, as scikit-learn computes it.
        let count = Double(documents.count)
        func idf(_ term: String) -> Double {
            log((1 + count) / (1 + Double(documentFrequency[term] ?? 0))) + 1
        }

        let vectors: [[String: Double]] = documents.map { document in
            var weights: [String: Double] = [:]
            for term in document {
                weights[term, default: 0] += 1
            }
            for (term, frequency) in weights {
                weights[term] = frequency * idf(term)
            }
            let norm = weights.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
            return norm > 0 ? weights.mapValues { $0 / norm } : [:]
        }

        let size = documents.count
        var values = [Double](repeating: 0, count: size * size)
        for row in 0..<size {
            values[row * size + row] = 1
            for column in (row + 1)..<size {
                let (small, large) = vectors[row].count <= vectors[column].count
                    ? (vectors[row], vectors[column])
                    : (vectors[column], vectors[row])
                let score = small.reduce(0) { $0 + $1.value * (large[$1.key] ?? 0) }
                values[row * size + column] = score
                values[column * size + row] = score
            }
        }
        return SimilarityMatrix(size: size, values: values)
    }

    /// Word-overlap similarity between sentences, ignoring stopwords and
    /// plural endings.
    public static func lexical(
        sentences: [String],
        stopwords: Set<String> = ProseStopwords.english
    ) -> SimilarityMatrix {
        let documents = sentences.map { sentence in
            ProseTokenizer.words(in: sentence)
                .filter { !$0.isNumeric }
                .map { KeywordExtractor.key(for: $0) }
                .filter { !stopwords.contains($0) }
                .map(lightStem)
        }
        return lexical(documents: documents)
    }

    /// The most similar pair of different items, or nil with fewer than two.
    ///
    /// - Parameter count: consider only the first `count` items, as a
    ///   heatmap that shows only part of the matrix would.
    public func mostSimilarPair(amongFirst count: Int? = nil) -> SimilarPair? {
        let limit = min(count ?? size, size)
        var best: SimilarPair?
        for row in 0..<max(limit, 0) {
            for column in (row + 1)..<limit where best.map({ self[row, column] > $0.similarity }) ?? true {
                best = SimilarPair(first: row, second: column, similarity: self[row, column])
            }
        }
        return best
    }

    /// The lowest and highest scores off the diagonal, for scaling colors, or
    /// nil with fewer than two items.
    public var offDiagonalRange: ClosedRange<Double>? {
        var lowest = Double.infinity
        var highest = -Double.infinity
        for row in 0..<size {
            for column in (row + 1)..<size {
                lowest = min(lowest, self[row, column])
                highest = max(highest, self[row, column])
            }
        }
        return lowest <= highest ? lowest...highest : nil
    }

    /// Folds plural endings together so "satellite" matches "satellites".
    static func lightStem(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("sses") { return String(word.dropLast(2)) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
            return String(word.dropLast())
        }
        return word
    }
}

/// Two items of a `SimilarityMatrix` and their score.
public struct SimilarPair: Hashable, Sendable {
    public let first: Int
    public let second: Int
    public let similarity: Double
}

/// Vector arithmetic for word and sentence embeddings.
public enum EmbeddingMath {
    public static func dot(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var sum = 0.0
        for index in a.indices {
            sum += a[index] * b[index]
        }
        return sum
    }

    public static func length(_ vector: [Double]) -> Double {
        dot(vector, vector).squareRoot()
    }

    /// The vector scaled to length 1, or unchanged when it has length 0.
    public static func normalized(_ vector: [Double]) -> [Double] {
        let magnitude = length(vector)
        return magnitude > 0 ? vector.map { $0 / magnitude } : vector
    }

    /// The cosine of the angle between two vectors: 1 for the same
    /// direction, 0 for unrelated, −1 for opposite. 0 when either is empty,
    /// zero, or they differ in length.
    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        let magnitudes = length(a) * length(b)
        return magnitudes > 0 ? dot(a, b) / magnitudes : 0
    }

    /// The vector a − b + c, which answers "b is to a as c is to what?":
    /// king − man + woman lands near queen. Each vector is normalized first so
    /// that no single word dominates (the 3CosAdd method). Returns an empty
    /// vector when the lengths differ.
    public static func analogy(_ a: [Double], minus b: [Double], plus c: [Double]) -> [Double] {
        guard a.count == b.count, b.count == c.count else { return [] }
        let unitA = normalized(a)
        let unitB = normalized(b)
        let unitC = normalized(c)
        return unitA.indices.map { unitA[$0] - unitB[$0] + unitC[$0] }
    }
}
