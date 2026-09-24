import ConnectFourKit
import Foundation

/// The two disc colors. You are always red and Claude is yellow; when Claude
/// plays itself, red moves first.
enum ConnectFourDiscColor: Hashable {
    case red
    case yellow

    var name: String {
        self == .red ? "Red" : "Yellow"
    }
}

/// Where everything sits on the stage.
///
/// Every length is a multiple of one cell, so the board scales with the stage.
/// From top to bottom: the lane where the next disc hovers, the row of
/// evaluation chips, the board, and its feet.
struct ConnectFourLayout: Equatable {
    // Proportions, in cells.
    static let padding: CGFloat = 0.24
    static let holeRadius: CGFloat = 0.40
    static let discRadius: CGFloat = 0.37
    static let chipWidth: CGFloat = 0.86
    static let chipHeight: CGFloat = 0.42
    static let gap: CGFloat = 0.10
    static let footHeight: CGFloat = 0.34
    static let cornerRadius: CGFloat = 0.34

    /// Height of the lane where a disc hovers before it drops.
    static let laneHeight: CGFloat = 2 * discRadius
    /// Distance in cells from the hover lane down to the top row's centers.
    static let laneToTopRow: CGFloat = discRadius + gap + chipHeight + gap + padding + 0.5

    static let widthInCells: CGFloat = 7 + 2 * padding
    static let boardHeightInCells: CGFloat = 6 + 2 * padding
    static let heightInCells: CGFloat = laneHeight + gap + chipHeight + gap + boardHeightInCells + footHeight

    // Margins in points: room for the stage's HUD above and its hint below.
    static let topMargin: CGFloat = 60
    static let bottomMargin: CGFloat = 46
    static let sideMargin: CGFloat = 24
    /// The largest cell, so the board stays a comfortable size on big screens.
    static let maximumUnit: CGFloat = 104

    /// Points per cell.
    let unit: CGFloat
    /// The blue frame of the board.
    let board: CGRect
    /// Center line of the hover lane.
    let laneY: CGFloat
    /// Center line of the evaluation chips.
    let chipY: CGFloat

    init(size: CGSize) {
        let width = max(size.width - 2 * Self.sideMargin, 120)
        let height = max(size.height - Self.topMargin - Self.bottomMargin, 120)
        let unit = min(width / Self.widthInCells, height / Self.heightInCells, Self.maximumUnit)
        self.unit = unit

        let top = Self.topMargin + (height - Self.heightInCells * unit) / 2
        let centerX = Self.sideMargin + width / 2
        laneY = top + Self.discRadius * unit
        chipY = top + (Self.laneHeight + Self.gap + Self.chipHeight / 2) * unit

        let boardTop = top + (Self.laneHeight + Self.gap + Self.chipHeight + Self.gap) * unit
        let boardWidth = Self.widthInCells * unit
        board = CGRect(
            x: centerX - boardWidth / 2,
            y: boardTop,
            width: boardWidth,
            height: Self.boardHeightInCells * unit
        )
    }

    func x(ofColumn column: Int) -> CGFloat {
        board.minX + (Self.padding + CGFloat(column) + 0.5) * unit
    }

    func y(ofRow row: Int) -> CGFloat {
        board.minY + (Self.padding + CGFloat(5 - row) + 0.5) * unit
    }

    func center(of position: C4Cell) -> CGPoint {
        CGPoint(x: x(ofColumn: position.column), y: y(ofRow: position.row))
    }

    var holeRadius: CGFloat {
        Self.holeRadius * unit
    }

    var discRadius: CGFloat {
        Self.discRadius * unit
    }

    var chipSize: CGSize {
        CGSize(width: Self.chipWidth * unit, height: Self.chipHeight * unit)
    }

    /// The square around the hole of a cell.
    func holeRect(column: Int, row: Int) -> CGRect {
        let radius = holeRadius
        return CGRect(x: x(ofColumn: column) - radius, y: y(ofRow: row) - radius, width: 2 * radius, height: 2 * radius)
    }

    /// The area that answers the pointer for a column: from the hover lane
    /// down to the bottom of the board.
    func target(forColumn column: Int) -> CGRect {
        let top = laneY - discRadius
        return CGRect(x: x(ofColumn: column) - unit / 2, y: top, width: unit, height: board.maxY - top)
    }

    /// The band above the board where the result banner appears.
    var bannerCenter: CGPoint {
        CGPoint(x: board.midX, y: (laneY - discRadius + board.minY) / 2)
    }
}

/// The falling-disc animation: free fall under gravity, then two small
/// bounces, measured in cells so it looks the same at any size.
enum ConnectFourPhysics {
    /// Gravity, in cells per second squared.
    static let gravity = 72.0
    /// The share of its speed a disc keeps when it bounces.
    static let restitution = 0.2
    /// How long a disc taken back by Undo takes to fade away.
    static let vanishDuration = 0.28

    /// Cells from the hover lane down to `row`.
    static func distance(toRow row: Int) -> Double {
        Double(ConnectFourLayout.laneToTopRow) + Double(5 - row)
    }

    /// Seconds from release until a disc dropped into `row` comes to rest.
    static func duration(toRow row: Int) -> Double {
        let fall = (2 * distance(toRow: row) / gravity).squareRoot()
        // Each bounce flies for 2v/g, and v shrinks by `restitution` each time.
        return fall * (1 + 2 * restitution * (1 + restitution))
    }

    /// How many cells above its resting place a disc dropped into `row` is,
    /// `elapsed` seconds after release.
    static func height(after elapsed: Double, row: Int) -> Double {
        let distance = distance(toRow: row)
        guard elapsed > 0 else { return distance }
        let fall = (2 * distance / gravity).squareRoot()
        if elapsed < fall {
            return distance - 0.5 * gravity * elapsed * elapsed
        }
        var time = elapsed - fall
        var speed = restitution * gravity * fall
        for _ in 0..<2 {
            let flight = 2 * speed / gravity
            if time < flight {
                return speed * time - 0.5 * gravity * time * time
            }
            time -= flight
            speed *= restitution
        }
        return 0
    }
}

/// Text for scores, statistics and verdicts.
enum ConnectFourFormat {
    /// A chip label: "Win in 5", "Loses in 4", "+12", "−3".
    static func label(for score: C4Score) -> String {
        switch score {
        case .win(let moves): return "Win in \(moves)"
        case .loss(let moves): return "Loses in \(moves)"
        case .draw: return "Draw"
        case .estimate(let value): return signed(value)
        }
    }

    /// An integer with an explicit sign and a true minus sign.
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\u{2212}\(-value)" }
        return "0"
    }

    /// "912", "48.2 K", "1.24 M".
    static func count(_ value: Int) -> String {
        switch value {
        case ..<1_000:
            return "\(value)"
        case ..<100_000:
            return String(format: "%.1f K", Double(value) / 1_000)
        case ..<1_000_000:
            return String(format: "%.0f K", Double(value) / 1_000)
        default:
            return String(format: "%.2f M", Double(value) / 1_000_000)
        }
    }

    static func seconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }

    static func moves(_ count: Int) -> String {
        count == 1 ? "1 move" : "\(count) moves"
    }

    /// One sentence on what the mover expects, from the score of the move it
    /// chose: "Claude expects to win in 9 moves."
    static func verdict(score: C4Score, mover: String, opponent: String) -> String {
        switch score {
        case .win(let moves):
            return moves == 1
                ? "\(mover) found the winning move."
                : "\(mover) expects to win in \(moves) moves."
        case .loss(let moves):
            return "\(mover) sees a forced loss: \(opponent) can win in \(Self.moves(moves))."
        case .draw:
            return "\(mover) expects a draw with best play."
        case .estimate(let value) where value >= 8:
            return "\(mover) likes its position (\(signed(value)))."
        case .estimate(let value) where value <= -8:
            return "\(mover) is under pressure (\(signed(value)))."
        case .estimate(let value):
            return "\(mover) sees a balanced game (\(signed(value)))."
        }
    }
}

extension C4Difficulty {
    /// The level's name in the picker.
    var title: String {
        switch self {
        case .casual: return "Casual"
        case .strong: return "Strong"
        case .ruthless: return "Ruthless"
        }
    }

    /// One line on how the level plays.
    var blurb: String {
        switch self {
        case .casual:
            return "Looks four discs ahead and plays loosely. Beatable."
        case .strong:
            return "Searches up to 12 discs ahead in half a second."
        case .ruthless:
            return "Deepens for 1.5 seconds with no limit, solving most endgames outright."
        }
    }
}
