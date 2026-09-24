/// How long and how deep an analysis may run.
public struct C4SearchLimits: Hashable, Sendable {
    /// The deepest iteration, in plies (single discs). 42 or more lets the
    /// search run to the end of the game.
    public var maxDepth: Int
    /// A wall-clock budget in seconds, or nil for none.
    ///
    /// Iterative deepening stops starting new iterations once about half the
    /// budget is spent, and abandons an iteration that runs past the budget.
    /// Either way the answer comes from the deepest iteration that finished.
    public var timeBudget: Double?

    public init(maxDepth: Int = 42, timeBudget: Double? = nil) {
        self.maxDepth = maxDepth
        self.timeBudget = timeBudget
    }

    /// Up to 0.8 seconds at unlimited depth, for showing the player an
    /// evaluation of every column.
    public static let analysis = C4SearchLimits(maxDepth: 42, timeBudget: 0.8)
}

/// What the engine thinks of a position: a score for every column that is not
/// full.
public struct C4Analysis: Sendable {
    /// The analyzed position.
    public let board: C4Board
    /// The score for dropping a disc into each column, indexed by column and
    /// seen from the player to move. Nil for a full column.
    public let scores: [C4Score?]
    /// Whether each column's score is final, indexed by column.
    ///
    /// Forced results are proven the moment they appear, but a quicker one
    /// may still turn up, because the search follows single-reply sequences
    /// past its nominal depth. A win or loss becomes exact once the
    /// iteration depth reaches its length, and every score is exact once the
    /// search reaches the end of the game.
    public let exactColumns: [Bool]
    /// The deepest iteration that finished, in plies.
    public let depth: Int
    /// Positions visited, across all iterations.
    public let nodes: Int
    /// Seconds spent.
    public let elapsed: Double
    /// The line of play the engine expects, starting with `bestColumn`. The
    /// line comes from the transposition table, so it may stop early.
    public let principalVariation: [Int]

    /// Whether every score is exact: the position is solved.
    public var isSolved: Bool {
        (0..<scores.count).allSatisfy { scores[$0] == nil || exactColumns[$0] }
    }

    /// The column with the best score. Ties go to the more central column.
    public var bestColumn: Int? {
        var best: (column: Int, score: C4Score)?
        for column in C4Analysis.centerOrder {
            guard let score = scores[column] else { continue }
            if best == nil || score > best!.score {
                best = (column, score)
            }
        }
        return best?.column
    }

    /// The score of `bestColumn`.
    public var bestScore: C4Score? {
        bestColumn.flatMap { scores[$0] }
    }

    /// The columns that have a score, from left to right.
    public var scoredColumns: [Int] {
        (0..<C4Board.columnCount).filter { scores[$0] != nil }
    }

    /// Search speed.
    public var nodesPerSecond: Double {
        elapsed > 0 ? Double(nodes) / elapsed : 0
    }

    /// Columns from the center outward, the engine's default preference.
    public static let centerOrder = [3, 2, 4, 1, 5, 0, 6]

    /// A copy with updated totals, used when the last iteration is cut short.
    func with(nodes: Int, elapsed: Double) -> C4Analysis {
        C4Analysis(
            board: board,
            scores: scores,
            exactColumns: exactColumns,
            depth: depth,
            nodes: nodes,
            elapsed: elapsed,
            principalVariation: principalVariation
        )
    }
}

/// A snapshot of an analysis in progress, reported about ten times a second
/// and after every iteration.
public struct C4SearchUpdate: Sendable {
    /// The deepest iteration finished so far.
    public let analysis: C4Analysis
    /// The iteration being worked on, one deeper than `analysis.depth`, or the
    /// same depth when the update marks the end of an iteration.
    public let searchingDepth: Int
    /// Positions visited so far, the unfinished iteration included.
    public let nodes: Int
    /// Seconds since the analysis began.
    public let elapsed: Double
}
