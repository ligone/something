/// The engine's verdict on a move, from the point of view of the player
/// making it.
///
/// Forced results are proven: `.win(inMoves: 3)` means the player can connect
/// four by their third disc from now, counting this move as the first,
/// however the opponent replies. Deeper search can only shorten the count,
/// and once `C4Analysis.exactColumns` marks the column, it is the quickest
/// possible. Anything the search could not settle is an `.estimate` from the
/// evaluation function.
public enum C4Score: Hashable, Sendable {
    /// The player wins by force, with their `inMoves`-th disc from now at the
    /// latest; 1 means this move wins on the spot.
    case win(inMoves: Int)
    /// The opponent wins by force, with their `inMoves`-th disc from now at
    /// the latest; 1 means they win with their very next disc.
    case loss(inMoves: Int)
    /// Best play by both sides fills the board with no four in a row. The
    /// engine reports this only once its search reaches the end of the game.
    case draw
    /// A heuristic judgment where the search could not see the end: positive
    /// favors the player, negative the opponent. Typical values stay within
    /// a few dozen.
    case estimate(Int)

    /// Whether the result is forced: a win or a loss.
    public var isDecisive: Bool {
        switch self {
        case .win, .loss: return true
        case .draw, .estimate: return false
        }
    }

    /// The score squeezed into -1...1, for drawing bars. Forced results sit
    /// between 0.8 and 1 in size, quicker ones larger; estimates stay within
    /// ±0.75 and flatten out as they grow.
    public var normalized: Double {
        switch self {
        case .win(let moves):
            return 1 - Double(min(max(moves, 1), 21) - 1) * 0.01
        case .loss(let moves):
            return -(1 - Double(min(max(moves, 1), 21) - 1) * 0.01)
        case .draw:
            return 0
        case .estimate(let value):
            let x = Double(value)
            return 0.75 * x / (abs(x) + 24)
        }
    }

    /// Orders scores from worst to best: slow losses beat quick ones, every
    /// estimate beats a loss, and a draw ranks just above an even estimate.
    private var rank: (Int, Int) {
        switch self {
        case .win(let moves): return (2_000_000 - moves, 0)
        case .loss(let moves): return (-2_000_000 + moves, 0)
        case .draw: return (0, 1)
        case .estimate(let value): return (min(max(value, -1_000_000), 1_000_000), 0)
        }
    }
}

extension C4Score: Comparable {
    public static func < (lhs: C4Score, rhs: C4Score) -> Bool {
        lhs.rank < rhs.rank
    }
}

extension C4Score: CustomStringConvertible {
    public var description: String {
        switch self {
        case .win(let moves): return "Win in \(moves)"
        case .loss(let moves): return "Loss in \(moves)"
        case .draw: return "Draw"
        case .estimate(let value): return value > 0 ? "+\(value)" : "\(value)"
        }
    }
}

extension C4Score {
    /// Converts a raw search value into a score.
    ///
    /// Raw values measure forced results by the total number of discs on the
    /// board when the game ends (see `C4Searcher.win`), which makes them
    /// independent of the path that reached a position. Turning one into "win
    /// in N" needs `discs`, the number of discs before the scored move.
    init(raw: Int, discs: Int, isExact: Bool) {
        if raw >= C4Searcher.decisive {
            let finalDiscs = C4Searcher.win - raw
            self = .win(inMoves: (finalDiscs - discs + 1) / 2)
        } else if raw <= -C4Searcher.decisive {
            let finalDiscs = C4Searcher.win + raw
            self = .loss(inMoves: (finalDiscs - discs) / 2)
        } else if raw == 0 && isExact {
            self = .draw
        } else {
            self = .estimate(raw)
        }
    }
}
