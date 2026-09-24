import Dispatch

/// The alpha-beta core: a depth-limited negamax search over raw bitboards.
///
/// ## Raw values
///
/// A forced result is scored by *when* the game ends: a win whose last disc
/// is the board's `n`-th disc is worth `win - n` to the winner and
/// `-(win - n)` to the loser. That prefers quick wins and slow losses, and
/// because `n` depends only on the position, never on the path to it, the
/// values can go straight into the transposition table. Evaluation values
/// stay far below `decisive`, so the two kinds never mix.
///
/// ## Invariant
///
/// The side to move at every searched node has no immediate win. The root
/// checks this for its children, and each node only plays moves that leave
/// the opponent no winning cell (Pascal Pons's "possible non-losing moves").
/// So a node never tests for its own wins, and it learns its losses for
/// free: it has lost when it has no non-losing move.
struct C4Searcher {
    /// The base of raw values for forced results.
    static let win = 10_000
    /// Raw values at least this far from zero are forced results.
    static let decisive = win - 64
    /// Larger than any raw value.
    static let infinity = 30_000

    // Bound kinds stored in the transposition table. Zero means "empty".
    private static let upperBound: UInt32 = 1
    private static let lowerBound: UInt32 = 2
    private static let exactBound: UInt32 = 3

    /// Tie-break priority of each column for move ordering, 4 bits per
    /// column from column 0 upward: 7 for the center, then 6 and 5 for its
    /// neighbors, out to 2 and 1 at the edges.
    private static let columnPriority: UInt32 = 0x0135_7642

    /// Number of 4-in-a-row lines through each cell, bottom row first.
    /// Central cells take part in more lines, so they are worth more.
    static let cellWeights: [[Int]] = [
        [3, 4, 5, 7, 5, 4, 3],
        [4, 6, 8, 10, 8, 6, 4],
        [5, 8, 11, 13, 11, 8, 5],
        [5, 8, 11, 13, 11, 8, 5],
        [4, 6, 8, 10, 8, 6, 4],
        [3, 4, 5, 7, 5, 4, 3],
    ]

    private let slots: UnsafeMutablePointer<UInt64>
    private let bucketCount: UInt64
    private let generation: UInt32
    private let deadline: UInt64
    private let shouldStop: () -> Bool
    private let heartbeat: (Int) -> Void
    private var nextHeartbeat: UInt64

    // `cellWeights` as four bit planes: weight = Σ 2ᵏ · [cell ∈ planeₖ], so
    // summing a player's weights takes four popcounts.
    private let plane0: UInt64
    private let plane1: UInt64
    private let plane2: UInt64
    private let plane3: UInt64

    /// Positions visited so far.
    private(set) var nodes = 0
    /// Whether the search stopped early, for time or because it was asked to.
    /// Values returned after that are meaningless.
    private(set) var isAborted = false

    /// - Parameters:
    ///   - deadline: `DispatchTime` uptime in nanoseconds after which to stop,
    ///     or nil for no limit.
    ///   - shouldStop: Polled about every thousand nodes; returning true stops
    ///     the search.
    ///   - heartbeat: Called with the node count about ten times a second
    ///     while the search runs.
    init(
        table: C4TranspositionTable,
        deadline: UInt64?,
        shouldStop: @escaping () -> Bool,
        heartbeat: @escaping (Int) -> Void
    ) {
        slots = table.slots
        bucketCount = UInt64(table.bucketCount)
        generation = table.beginSearch()
        self.deadline = deadline ?? 0
        self.shouldStop = shouldStop
        self.heartbeat = heartbeat
        nextHeartbeat = DispatchTime.now().uptimeNanoseconds &+ 100_000_000

        var planes: [UInt64] = [0, 0, 0, 0]
        for row in 0..<C4Board.rowCount {
            for column in 0..<C4Board.columnCount {
                let weight = Self.cellWeights[row][column]
                for bit in 0..<4 where weight & (1 << bit) != 0 {
                    planes[bit] |= C4Bits.cell(column: column, row: row)
                }
            }
        }
        plane0 = planes[0]
        plane1 = planes[1]
        plane2 = planes[2]
        plane3 = planes[3]
    }

    // MARK: - Search

    /// The negamax value of a position for the side to move, searched `depth`
    /// plies deep within the window `alpha...beta`.
    ///
    /// The result is fail-soft: a value at or below `alpha` is an upper
    /// bound, one at or above `beta` a lower bound, and anything in between
    /// is exact.
    mutating func search(
        _ current: UInt64,
        _ mask: UInt64,
        _ discs: Int,
        _ depth: Int,
        _ alphaIn: Int,
        _ betaIn: Int
    ) -> Int {
        nodes &+= 1
        if nodes & 1023 == 0 {
            poll()
        }
        if isAborted { return 0 }

        var alpha = alphaIn
        var beta = betaIn

        // Pons's non-losing moves. Block an open opponent threat if there is
        // one; lose if there are two; never fill the cell beneath an opponent
        // threat, because that hands them the cell.
        let landing = C4Bits.landingCells(mask)
        let opponentWins = C4Bits.winningCells(current ^ mask, mask)
        var candidates = landing
        let forced = landing & opponentWins
        if forced != 0 {
            if forced & (forced &- 1) != 0 {
                return -(Self.win - (discs + 2))
            }
            candidates = forced
        }
        candidates &= ~(opponentWins &>> 1)
        if candidates == 0 {
            return -(Self.win - (discs + 2))
        }

        // Two or fewer empty cells, no win for us and a safe move: a draw.
        if discs >= 40 {
            return 0
        }

        // Mate-distance bounds. We cannot win before our next-but-one disc,
        // and our safe move means the opponent cannot win with their next.
        let ceiling = Self.win - (discs + 3)
        if beta > ceiling {
            beta = ceiling
            if alpha >= beta { return beta }
        }
        let floor = -(Self.win - (discs + 4))
        if alpha < floor {
            alpha = floor
            if alpha >= beta { return alpha }
        }

        if depth <= 0 {
            return evaluate(current, mask, discs, opponentWins)
        }

        // Transposition table lookup, in both slots of the bucket.
        let key = current &+ mask
        let tag = UInt32(truncatingIfNeeded: key)
        let bucket = Int(truncatingIfNeeded: key % bucketCount) &<< 1
        var entry = slots[bucket]
        if UInt32(truncatingIfNeeded: entry &>> 32) != tag {
            entry = slots[bucket &+ 1]
        }
        var hashColumn = -1
        if UInt32(truncatingIfNeeded: entry &>> 32) == tag {
            let data = UInt32(truncatingIfNeeded: entry)
            let bound = (data &>> 22) & 3
            if bound != 0 {
                hashColumn = Int((data &>> 24) & 0xF) - 1
                if Int((data &>> 16) & 0x3F) >= depth {
                    let value = Int(Int16(bitPattern: UInt16(truncatingIfNeeded: data)))
                    if bound == Self.exactBound { return value }
                    if bound == Self.lowerBound && value >= beta { return value }
                    if bound == Self.upperBound && value <= alpha { return value }
                }
            }
        }

        // Move ordering, packed as one byte per column: the table's best
        // move first, then moves that open the most new threats of our own,
        // then central columns.
        var keys: UInt64 = 0
        var remaining: UInt32 = 0
        var column = 0
        while column < 7 {
            let move = candidates & C4Bits.column(column)
            if move != 0 {
                let sortKey: UInt64
                if column == hashColumn {
                    sortKey = 255
                } else {
                    let threats = C4Bits.winningCells(current | move, mask).nonzeroBitCount
                    sortKey = UInt64(min(threats, 30) &* 8) &+ Self.priority(column)
                }
                keys |= sortKey &<< (column &* 8)
                remaining |= 1 &<< UInt32(column)
            }
            column &+= 1
        }

        // A single legal reply costs no branching, so search it one ply
        // deeper. Forced sequences are where Connect Four is decided.
        let childDepth = candidates & (candidates &- 1) == 0 ? depth : depth - 1
        let childCurrent = current ^ mask
        let alphaStart = alpha
        var bestValue = -Self.infinity
        var bestColumn = -1
        var isFirst = true

        while remaining != 0 {
            // Select the highest remaining key.
            var pick = 0
            var pickKey: UInt64 = 0
            var scan = remaining
            while scan != 0 {
                let c = scan.trailingZeroBitCount
                scan &= scan &- 1
                let k = (keys &>> (c &* 8)) & 0xFF
                if k > pickKey {
                    pickKey = k
                    pick = c
                }
            }
            remaining &= ~(1 &<< UInt32(pick))

            let childMask = mask | (candidates & C4Bits.column(pick))
            var value: Int
            if isFirst {
                value = -search(childCurrent, childMask, discs + 1, childDepth, -beta, -alpha)
                isFirst = false
            } else {
                // Principal variation search: prove the move is no better
                // with a null window, and re-search only if it is.
                value = -search(childCurrent, childMask, discs + 1, childDepth, -alpha - 1, -alpha)
                if value > alpha && value < beta && !isAborted {
                    value = -search(childCurrent, childMask, discs + 1, childDepth, -beta, -alpha)
                }
            }
            if isAborted { return 0 }

            if value > bestValue {
                bestValue = value
                bestColumn = pick
                if value > alpha {
                    alpha = value
                    if alpha >= beta { break }
                }
            }
        }

        let bound: UInt32
        if bestValue <= alphaStart {
            bound = Self.upperBound
        } else if bestValue >= beta {
            bound = Self.lowerBound
        } else {
            bound = Self.exactBound
        }
        store(bucket: bucket, tag: tag, value: bestValue, depth: depth, bound: bound, column: bestColumn)
        return bestValue
    }

    // MARK: - Evaluation

    /// A heuristic value for the side to move, used at the search horizon.
    ///
    /// It adds up two things for each player:
    ///
    /// - **Cell weights.** Each disc counts the lines that pass through its
    ///   cell, so central discs are worth the most.
    /// - **Threats.** Empty cells that would complete four. Their row parity
    ///   matters: when a column fills up, the first player tends to get the
    ///   odd rows and the second player the even rows (counting from 1 at
    ///   the bottom). So a threat on your own parity is a real weapon, and
    ///   two threats stacked one above the other usually win outright.
    @inline(__always)
    private func evaluate(_ current: UInt64, _ mask: UInt64, _ discs: Int, _ opponentWins: UInt64) -> Int {
        let opponent = current ^ mask
        let ownWins = C4Bits.winningCells(current, mask)
        let firstToMove = discs & 1 == 0
        let ownRows = firstToMove ? C4Bits.oddRows : C4Bits.evenRows
        let opponentRows = firstToMove ? C4Bits.evenRows : C4Bits.oddRows

        var value = cellValue(current) - cellValue(opponent)
        value += threatValue(ownWins, ownRows) - threatValue(opponentWins, opponentRows)
        return (value &+ Self.tempo) / 2
    }

    /// A small bonus for having the move. Without it the evaluation favors
    /// whoever just dropped a disc, so estimates swing between odd and even
    /// search depths. The value won head-to-head matches against 0, 3, 5, 10
    /// and 12.
    private static let tempo = 8

    @inline(__always)
    private func cellValue(_ discs: UInt64) -> Int {
        (discs & plane0).nonzeroBitCount
            &+ (discs & plane1).nonzeroBitCount &* 2
            &+ (discs & plane2).nonzeroBitCount &* 4
            &+ (discs & plane3).nonzeroBitCount &* 8
    }

    @inline(__always)
    private func threatValue(_ threats: UInt64, _ favoredRows: UInt64) -> Int {
        let favored = (threats & favoredRows).nonzeroBitCount
        let others = threats.nonzeroBitCount &- favored
        let stacked = (threats & (threats &>> 1)).nonzeroBitCount
        return favored &* 12 &+ others &* 5 &+ stacked &* 16
    }

    // MARK: - Transposition table

    // Slot layout: key bits 0–31 in the high half; in the low half, the value
    // as Int16 (bits 0–15), depth (16–21), bound kind (22–23), best
    // column + 1 (24–27) and the search generation (28–31).
    @inline(__always)
    private func store(bucket: Int, tag: UInt32, value: Int, depth: Int, bound: UInt32, column: Int) {
        let data = UInt32(UInt16(bitPattern: Int16(truncatingIfNeeded: value)))
            | UInt32(truncatingIfNeeded: min(depth, 63)) &<< 16
            | bound &<< 22
            | UInt32(truncatingIfNeeded: column + 1) &<< 24
            | generation &<< 28
        let entry = UInt64(tag) &<< 32 | UInt64(data)

        // The first slot keeps the deepest result of this search; anything
        // it turns away goes to the second slot.
        let deep = slots[bucket]
        let deepData = UInt32(truncatingIfNeeded: deep)
        if UInt32(truncatingIfNeeded: deep &>> 32) == tag
            || deepData &>> 28 != generation
            || Int((deepData &>> 16) & 0x3F) <= depth {
            slots[bucket] = entry
        } else {
            slots[bucket &+ 1] = entry
        }
    }

    /// The best move stored for a position, if the table has one.
    func storedMove(for board: C4Board) -> Int? {
        let key = board.key
        let tag = UInt32(truncatingIfNeeded: key)
        let bucket = Int(truncatingIfNeeded: key % bucketCount) &<< 1
        for slot in bucket...(bucket + 1) {
            let entry = slots[slot]
            let data = UInt32(truncatingIfNeeded: entry)
            guard UInt32(truncatingIfNeeded: entry &>> 32) == tag, (data &>> 22) & 3 != 0 else { continue }
            let column = Int((data &>> 24) & 0xF) - 1
            return column >= 0 ? column : nil
        }
        return nil
    }

    /// The line of play the search expects after `column`, read back from
    /// the table's best moves.
    func principalVariation(from board: C4Board, first column: Int, maxLength: Int) -> [Int] {
        guard var position = board.playing(column) else { return [] }
        var line = [column]
        if position.hasFour(for: board.playerToMove) { return line }

        while line.count < maxLength, !position.isFull {
            // The search never enters a position with a win on the spot, and
            // does not store positions that are lost on the spot, so finish
            // those lines by hand: take the win, or block one of the threats.
            if let winning = (0..<7).first(where: position.isWinningMove) {
                line.append(winning)
                break
            }
            let opponentWins = C4Bits.winningCells(position.current ^ position.mask, position.mask)
                & C4Bits.landingCells(position.mask)
            let next = storedMove(for: position)
                ?? (opponentWins != 0 ? opponentWins.trailingZeroBitCount / 7 : nil)
            guard let column = next, let after = position.playing(column) else { break }
            line.append(column)
            position = after
        }
        return line
    }

    // MARK: - Limits

    @inline(__always)
    private static func priority(_ column: Int) -> UInt64 {
        UInt64((columnPriority &>> (column &* 4)) & 0xF)
    }

    private mutating func poll() {
        if shouldStop() {
            isAborted = true
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        if deadline != 0 && now >= deadline {
            isAborted = true
            return
        }
        if now >= nextHeartbeat {
            nextHeartbeat = now &+ 100_000_000
            heartbeat(nodes)
        }
    }
}
