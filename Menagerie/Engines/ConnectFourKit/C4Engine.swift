import Dispatch
import Foundation

/// A Connect Four engine: iterative-deepening alpha-beta search that scores
/// every legal column of a position.
///
/// The engine owns a transposition table (16 MB by default) that carries
/// over from one analysis to the next, so it keeps what it learned about
/// the previous move. Calls are serialized: an analysis started while
/// another is running waits for it to finish, so stop the old one first
/// with `shouldStop`.
///
///     let engine = C4Engine()
///     let analysis = engine.analyze(board, limits: C4Difficulty.strong.limits)
///     analysis.bestColumn    // 3
///     analysis.scores[3]     // C4Score.estimate(4), or .win(inMoves: 5), …
public final class C4Engine: @unchecked Sendable {
    private let table: C4TranspositionTable
    private let lock = NSLock()

    /// An engine whose transposition table has at least `tableSize` slots of
    /// 8 bytes each.
    public init(tableSize: Int = 1 << 21) {
        table = C4TranspositionTable(minimumSize: tableSize)
    }

    /// Forgets everything the transposition table has learned.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        table.clear()
    }

    /// Scores every legal column of `board` for the player to move.
    ///
    /// Winning on the spot and moves that hand the opponent a win are
    /// scored without searching. Every other column gets a full-window
    /// alpha-beta search, repeated one ply deeper each iteration until the
    /// limits run out or every score is exact.
    ///
    /// - Parameters:
    ///   - limits: How deep and how long to search.
    ///   - shouldStop: Polled about every thousand nodes; return true to stop
    ///     early. The result then comes from the last finished iteration.
    ///   - onUpdate: Called on the searching thread after each iteration and
    ///     about ten times a second in between.
    public func analyze(
        _ board: C4Board,
        limits: C4SearchLimits = C4SearchLimits(),
        shouldStop: () -> Bool = { false },
        onUpdate: (C4SearchUpdate) -> Void = { _ in }
    ) -> C4Analysis {
        lock.lock()
        defer { lock.unlock() }
        return withoutActuallyEscaping(shouldStop) { shouldStop in
            withoutActuallyEscaping(onUpdate) { onUpdate in
                run(board, limits: limits, shouldStop: shouldStop, onUpdate: onUpdate)
            }
        }
    }

    /// The best column for the player to move, or nil if the game is over.
    public func bestMove(for board: C4Board, limits: C4SearchLimits = C4SearchLimits()) -> Int? {
        analyze(board, limits: limits).bestColumn
    }

    // MARK: - Iterative deepening

    private func run(
        _ board: C4Board,
        limits: C4SearchLimits,
        shouldStop: @escaping () -> Bool,
        onUpdate: @escaping (C4SearchUpdate) -> Void
    ) -> C4Analysis {
        let start = DispatchTime.now().uptimeNanoseconds
        func secondsSinceStart() -> Double {
            Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9
        }

        let discs = board.moveCount
        let emptyCells = C4Board.cellCount - discs
        let columns = C4Board.columnCount

        guard !board.isGameOver else {
            return C4Analysis(
                board: board,
                scores: Array(repeating: nil, count: columns),
                exactColumns: Array(repeating: false, count: columns),
                depth: 0,
                nodes: 0,
                elapsed: 0,
                principalVariation: []
            )
        }

        // Settle what needs no search: a win on the spot, and moves that let
        // the opponent win on the spot. Every other column gets a child
        // position to search, in which the opponent has no immediate win, as
        // the searcher requires.
        var raw = [Int?](repeating: nil, count: columns)
        var settled = [Bool](repeating: false, count: columns)
        var children = [C4Board?](repeating: nil, count: columns)
        for column in 0..<columns {
            guard let child = board.playing(column) else { continue }
            if board.isWinningMove(column) {
                raw[column] = C4Searcher.win - (discs + 1)
                settled[column] = true
            } else if child.canWinNext {
                raw[column] = -(C4Searcher.win - (discs + 2))
                settled[column] = true
            } else {
                children[column] = child
            }
        }

        var latest = Self.analysis(
            of: board,
            raw: raw,
            settled: settled,
            depth: 0,
            nodes: 0,
            elapsed: secondsSinceStart(),
            isExhaustive: false,
            principalVariation: []
        )
        // Nothing to search when every legal column wins or loses on the spot.
        if children.allSatisfy({ $0 == nil }) {
            return Self.analysis(
                of: board,
                raw: raw,
                settled: settled,
                depth: 1,
                nodes: 0,
                elapsed: secondsSinceStart(),
                isExhaustive: false,
                principalVariation: Self.bestColumn(raw).map { [$0] } ?? []
            )
        }

        var searchingDepth = 1
        let deadline = limits.timeBudget.map { start &+ UInt64(max(0, $0) * 1e9) }
        var searcher = C4Searcher(
            table: table,
            deadline: deadline,
            shouldStop: shouldStop,
            heartbeat: { nodes in
                onUpdate(C4SearchUpdate(
                    analysis: latest,
                    searchingDepth: searchingDepth,
                    nodes: nodes,
                    elapsed: secondsSinceStart()
                ))
            }
        )

        var order = C4Analysis.centerOrder
        let maxDepth = max(1, min(limits.maxDepth, emptyCells))
        for depth in 1...maxDepth {
            searchingDepth = depth
            var values = raw
            var finished = true
            for column in order where !settled[column] {
                guard let child = children[column] else { continue }
                let value = -searcher.search(
                    child.current, child.mask, child.moveCount, depth - 1,
                    -C4Searcher.infinity, C4Searcher.infinity
                )
                if searcher.isAborted {
                    finished = false
                    break
                }
                values[column] = value
            }
            if !finished { break }

            raw = values
            // A forced result is proven as soon as it appears, but single-
            // reply extensions can surface a slow mate before a quick one.
            // Once the iteration is as deep as the mate is long, no quicker
            // mate can hide beyond the horizon: the score is final, and the
            // column needs no more search.
            for column in 0..<columns {
                if let value = raw[column], abs(value) >= C4Searcher.decisive,
                   C4Searcher.win - abs(value) - discs <= depth {
                    settled[column] = true
                }
            }

            // A search as deep as the empty cells sees every game to its end.
            let isExhaustive = depth >= emptyCells
            let bestColumn = Self.bestColumn(raw)
            let line = bestColumn.map {
                searcher.principalVariation(from: board, first: $0, maxLength: depth + 1)
            } ?? []
            latest = Self.analysis(
                of: board,
                raw: raw,
                settled: settled,
                depth: depth,
                nodes: searcher.nodes,
                elapsed: secondsSinceStart(),
                isExhaustive: isExhaustive,
                principalVariation: line
            )
            onUpdate(C4SearchUpdate(
                analysis: latest,
                searchingDepth: depth,
                nodes: latest.nodes,
                elapsed: latest.elapsed
            ))

            if latest.isSolved { break }
            // The next iteration usually costs a few times this one, so do
            // not start it unless it has a fair chance to finish.
            if let budget = limits.timeBudget, secondsSinceStart() > budget * 0.45 { break }

            // Search the most promising columns first next time; alpha-beta
            // inside each column already reuses the table's best moves.
            order.sort { a, b in
                let va = raw[a] ?? Int.min
                let vb = raw[b] ?? Int.min
                if va != vb { return va > vb }
                return Self.centerRank(a) < Self.centerRank(b)
            }
        }

        return latest.with(nodes: searcher.nodes, elapsed: secondsSinceStart())
    }

    // MARK: - Helpers

    /// Packages raw root values. A score is exact when its column is settled
    /// (a forced result at its final distance) or when the search reached
    /// the end of the game.
    private static func analysis(
        of board: C4Board,
        raw: [Int?],
        settled: [Bool],
        depth: Int,
        nodes: Int,
        elapsed: Double,
        isExhaustive: Bool,
        principalVariation: [Int]
    ) -> C4Analysis {
        let scores = raw.map { value in
            value.map { C4Score(raw: $0, discs: board.moveCount, isExact: isExhaustive) }
        }
        let exact = (0..<raw.count).map { raw[$0] != nil && (settled[$0] || isExhaustive) }
        return C4Analysis(
            board: board,
            scores: scores,
            exactColumns: exact,
            depth: depth,
            nodes: nodes,
            elapsed: elapsed,
            principalVariation: principalVariation
        )
    }

    private static func bestColumn(_ raw: [Int?]) -> Int? {
        var best: (column: Int, value: Int)?
        for column in C4Analysis.centerOrder {
            guard let value = raw[column] else { continue }
            if best == nil || value > best!.value {
                best = (column, value)
            }
        }
        return best?.column
    }

    private static func centerRank(_ column: Int) -> Int {
        C4Analysis.centerOrder.firstIndex(of: column) ?? column
    }
}

/// A flag one thread raises to stop a search running on another.
///
///     let flag = C4StopFlag()
///     engine.analyze(board, shouldStop: { flag.isRaised })
///     // elsewhere:
///     flag.raise()
public final class C4StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    public init() {}

    /// Asks the search to stop.
    public func raise() {
        lock.lock()
        raised = true
        lock.unlock()
    }

    /// Whether `raise()` has been called.
    public var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }
}
