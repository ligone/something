import Foundation

/// How hard the engine plays: how long it searches, and how it picks a move
/// from the resulting analysis.
public enum C4Difficulty: String, CaseIterable, Identifiable, Sendable {
    /// Looks four plies ahead and picks at random, weighted toward the better
    /// moves. It takes a win on the spot and blocks one, but it can be
    /// outplayed.
    case casual
    /// Up to 12 plies within half a second, then plays the best move,
    /// choosing at random among moves with nearly the same score.
    case strong
    /// Deepens for up to 1.5 seconds with no depth cap, which solves most
    /// positions past the opening outright, then plays the best move.
    case ruthless

    public var id: String { rawValue }

    /// The search limits for this level.
    public var limits: C4SearchLimits {
        switch self {
        case .casual: return C4SearchLimits(maxDepth: 4, timeBudget: 0.3)
        case .strong: return C4SearchLimits(maxDepth: 12, timeBudget: 0.5)
        case .ruthless: return C4SearchLimits(maxDepth: 42, timeBudget: 1.5)
        }
    }

    /// Picks the column to play from an analysis of the current position, or
    /// returns nil if no column has a score.
    public func chooseColumn<Generator: RandomNumberGenerator>(
        from analysis: C4Analysis,
        using generator: inout Generator
    ) -> Int? {
        let options: [(column: Int, score: C4Score)] = analysis.scoredColumns.compactMap { column in
            analysis.scores[column].map { (column: column, score: $0) }
        }
        guard let best = options.map({ $0.score }).max() else { return nil }

        // Every level takes a win on the spot.
        if best == .win(inMoves: 1) {
            return options.first { $0.score == best }?.column
        }

        switch self {
        case .casual:
            return Self.weightedChoice(from: options, using: &generator)
        case .strong:
            let pool = options.filter { Self.isClose($0.score, to: best) }
            return pool.randomElement(using: &generator)?.column
        case .ruthless:
            let pool = options.filter { $0.score == best }
            return pool.randomElement(using: &generator)?.column
        }
    }

    /// Picks the column for the player to move with the default random
    /// source.
    public func chooseColumn(from analysis: C4Analysis) -> Int? {
        var generator = SystemRandomNumberGenerator()
        return chooseColumn(from: analysis, using: &generator)
    }

    /// Whether `score` is as good as `best`, or a whisker behind it when both
    /// are estimates.
    private static func isClose(_ score: C4Score, to best: C4Score) -> Bool {
        if score == best { return true }
        if case .estimate(let a) = score, case .estimate(let b) = best {
            return b - a <= 1
        }
        return false
    }

    /// A softmax pick: each move gets weight exp(score / temperature), so
    /// good moves come up often and poor ones now and then. A move that lets
    /// the opponent win on the spot is avoided while there is any other.
    private static func weightedChoice<Generator: RandomNumberGenerator>(
        from options: [(column: Int, score: C4Score)],
        using generator: inout Generator
    ) -> Int? {
        let safe = options.filter { $0.score != .loss(inMoves: 1) }
        let pool = safe.isEmpty ? options : safe
        guard let top = pool.map({ $0.score.normalized }).max() else { return nil }

        let temperature = 0.16
        let weights = pool.map { exp(($0.score.normalized - top) / temperature) }
        let total = weights.reduce(0, +)
        var ticket = Double.random(in: 0..<total, using: &generator)
        for (option, weight) in zip(pool, weights) {
            if ticket < weight { return option.column }
            ticket -= weight
        }
        return pool.last?.column
    }
}

/// SplitMix64: a tiny, fast random number generator that can be seeded, for
/// games and tests that must be repeatable.
public struct C4SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
