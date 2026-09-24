import Foundation
import MazeKit

/// What a click or drag on the maze does.
enum MazeTool: String, CaseIterable, Identifiable {
    case wall, mud, erase, start, goal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wall: "Wall"
        case .mud: "Mud"
        case .erase: "Erase"
        case .start: "Start"
        case .goal: "Goal"
        }
    }

    var systemImage: String {
        switch self {
        case .wall: "square.fill"
        case .mud: "drop.fill"
        case .erase: "eraser"
        case .start: "figure.walk"
        case .goal: "flag.checkered"
        }
    }

    /// A tooltip for the tool's button.
    var help: String {
        switch self {
        case .wall: "Paint walls. Start a stroke on a wall to erase instead."
        case .mud: "Paint mud, which costs \(MazeCell.mudCost) to cross. Start on mud to clear it."
        case .erase: "Clear walls and mud back to open floor."
        case .start: "Place the start. You can also drag the start marker with any tool."
        case .goal: "Place the goal. You can also drag the goal marker with any tool."
        }
    }

    /// The stage hint shown while the tool is selected and nothing is animating.
    var stageHint: String {
        switch self {
        case .wall: "Drag to draw walls · drag the start or goal to move it"
        case .mud: "Drag to spread mud; it costs \(MazeCell.mudCost) to wade through"
        case .erase: "Drag to clear walls and mud"
        case .start: "Click or drag to place the start"
        case .goal: "Click or drag to place the goal"
        }
    }
}

/// The two markers a search runs between.
enum MazeEndpoint {
    case start, goal
}

/// Maze size presets. Each preset aims for a number of cells, and its
/// shape follows the stage's aspect ratio so the maze fills the stage.
enum MazeSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    private var targetCells: Double {
        switch self {
        case .small: 750
        case .medium: 1_900
        case .large: 4_600
        }
    }

    /// Odd grid dimensions of roughly ``targetCells`` cells, shaped to `aspectRatio` (width ÷ height).
    func dimensions(aspectRatio: Double) -> (width: Int, height: Int) {
        let aspect = min(max(aspectRatio, 0.5), 2.5)
        let width = Self.nearestOdd((targetCells * aspect).squareRoot())
        let height = Self.nearestOdd(targetCells / Double(width))
        return (max(width, 9), max(height, 9))
    }

    private static func nearestOdd(_ value: Double) -> Int {
        let rounded = Int(value.rounded())
        return rounded.isMultiple(of: 2) ? rounded + 1 : rounded
    }
}

/// Maps the speed slider to playback rates.
enum MazePlaybackSpeed {
    /// The maze size, in cells, that the slider's rates are quoted for. Bigger
    /// mazes play proportionally faster, so an animation takes about as long
    /// at any size.
    static let referenceCells = 1_900.0

    /// Carving takes many small steps per cell, so it plays this much faster than search.
    static let carvingBoost = 6.0

    /// The slider's resting position: a brisk show that is still easy to follow.
    static let defaultSlider = 0.62

    /// Search steps per second for a slider position in 0…1: logarithmic, from
    /// 2 steps a second, slow enough to follow one at a time, up to 10,000.
    static func stepsPerSecond(slider: Double) -> Double {
        2 * pow(10, 3.7 * min(max(slider, 0), 1))
    }

    /// A compact label such as "390 steps/s" or "8.2k steps/s".
    static func label(stepsPerSecond rate: Double) -> String {
        if rate >= 1_000 {
            return String(format: "%.1fk steps/s", rate / 1_000)
        }
        if rate >= 10 {
            return "\(Int(rate.rounded())) steps/s"
        }
        return String(format: "%.1f steps/s", rate)
    }
}

/// One solver's results in the comparison.
struct MazeComparisonRow: Identifiable, Equatable {
    let solver: MazeSolver
    let nodesExpanded: Int
    let pathLength: Int
    let pathCost: Int
    let foundGoal: Bool

    var id: MazeSolver { solver }

    init(_ trace: SearchTrace) {
        solver = trace.solver
        nodesExpanded = trace.stats.nodesExpanded
        pathLength = trace.stats.pathLength
        pathCost = trace.stats.pathCost
        foundGoal = trace.stats.foundGoal
    }
}
