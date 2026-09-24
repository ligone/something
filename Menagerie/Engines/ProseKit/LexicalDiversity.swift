/// How varied a text's vocabulary is.
///
/// The type–token ratio (distinct words over total words) is intuitive but
/// falls as any text grows, because common words keep repeating. MTLD, the
/// Measure of Textual Lexical Diversity (McCarthy & Jarvis, 2010), doesn't:
/// it reports how many words in a row it takes, on average, for the running
/// type–token ratio to sink to 0.72. Higher means richer vocabulary; typical
/// prose scores 70–100.
public struct LexicalDiversity: Hashable, Sendable {
    /// Words counted, with repeats.
    public let tokenCount: Int
    /// Distinct words.
    public let typeCount: Int
    /// Words that occur exactly once (hapax legomena).
    public let hapaxCount: Int
    /// MTLD, or nil when the text is too short or too varied for the running
    /// ratio to fall at all.
    public let mtld: Double?

    /// The threshold McCarthy and Jarvis chose for MTLD.
    public static let mtldThreshold = 0.72

    /// - Parameter words: the words of a text, already normalized (for
    ///   example lowercased) so that equal words compare equal.
    public init(words: [String]) {
        var frequencies: [String: Int] = [:]
        for word in words {
            frequencies[word, default: 0] += 1
        }
        tokenCount = words.count
        typeCount = frequencies.count
        hapaxCount = frequencies.values.filter { $0 == 1 }.count
        mtld = Self.mtld(of: words)
    }

    /// Distinct words divided by total words; 0 for no words.
    public var typeTokenRatio: Double {
        tokenCount == 0 ? 0 : Double(typeCount) / Double(tokenCount)
    }

    /// MTLD: the mean of a forward and a backward pass, each dividing the
    /// word count by the number of "factors", stretches over which the running
    /// type–token ratio falls to `threshold`. A final partial stretch counts
    /// as the fraction of the way it got there.
    public static func mtld(of words: [String], threshold: Double = mtldThreshold) -> Double? {
        let passes = [mtldPass(words, threshold: threshold), mtldPass(Array(words.reversed()), threshold: threshold)]
            .compactMap { $0 }
        guard !passes.isEmpty else { return nil }
        return passes.reduce(0, +) / Double(passes.count)
    }

    private static func mtldPass(_ words: [String], threshold: Double) -> Double? {
        var factors = 0.0
        var types = Set<String>()
        var length = 0
        for word in words {
            types.insert(word)
            length += 1
            if Double(types.count) / Double(length) <= threshold {
                factors += 1
                types.removeAll(keepingCapacity: true)
                length = 0
            }
        }
        if length > 0 {
            let ratio = Double(types.count) / Double(length)
            factors += (1 - ratio) / (1 - threshold)
        }
        guard factors > 0 else { return nil }
        return Double(words.count) / factors
    }
}
