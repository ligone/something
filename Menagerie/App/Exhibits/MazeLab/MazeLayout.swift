import Foundation
import MazeKit

/// Where the maze sits on the stage. The layout scales the grid to fit, snaps
/// the cell size and origin to whole device pixels so every edge is crisp,
/// and converts between points and cells.
struct MazeLayout: Equatable {
    /// Room left clear around the board: the stage HUD sits at the top and the hint at the bottom.
    static let insets = (top: 60.0, leading: 24.0, bottom: 48.0, trailing: 24.0)

    let columns: Int
    let rows: Int
    let cellSize: CGFloat
    let origin: CGPoint

    /// The part of a stage of the given size that the board may occupy.
    static func boardArea(in size: CGSize) -> CGRect {
        let x = CGFloat(insets.leading)
        let y = CGFloat(insets.top)
        let width = max(size.width - CGFloat(insets.leading + insets.trailing), 1)
        let height = max(size.height - CGFloat(insets.top + insets.bottom), 1)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    init(columns: Int, rows: Int, area: CGRect, displayScale: CGFloat) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        let scale = max(displayScale, 1)
        let fitWidth = area.width / CGFloat(self.columns)
        let fitHeight = area.height / CGFloat(self.rows)
        let snapped = (min(fitWidth, fitHeight) * scale).rounded(.down) / scale
        cellSize = max(snapped, 1 / scale)
        let boardWidth = cellSize * CGFloat(self.columns)
        let boardHeight = cellSize * CGFloat(self.rows)
        let x = ((area.midX - boardWidth / 2) * scale).rounded() / scale
        let y = ((area.midY - boardHeight / 2) * scale).rounded() / scale
        origin = CGPoint(x: x, y: y)
    }

    /// The whole board.
    var boardRect: CGRect {
        CGRect(x: origin.x, y: origin.y, width: cellSize * CGFloat(columns), height: cellSize * CGFloat(rows))
    }

    func rect(x: Int, y: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(x) * cellSize, y: origin.y + CGFloat(y) * cellSize, width: cellSize, height: cellSize)
    }

    func rect(of point: MazePoint) -> CGRect {
        rect(x: point.x, y: point.y)
    }

    /// The rectangle of the cell at a row-major index.
    func rect(index: Int) -> CGRect {
        rect(x: index % columns, y: index / columns)
    }

    func center(of point: MazePoint) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(point.x) + 0.5) * cellSize, y: origin.y + (CGFloat(point.y) + 0.5) * cellSize)
    }

    /// The cell under a location, or `nil` when the location is off the board.
    func cell(at location: CGPoint) -> MazePoint? {
        let column = Int(((location.x - origin.x) / cellSize).rounded(.down))
        let row = Int(((location.y - origin.y) / cellSize).rounded(.down))
        guard column >= 0, row >= 0, column < columns, row < rows else { return nil }
        return MazePoint(x: column, y: row)
    }
}
