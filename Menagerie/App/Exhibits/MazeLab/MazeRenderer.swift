import Foundation
import MazeKit
import SwiftUI

/// Draws Maze Lab's layers into a `GraphicsContext`.
///
/// Every layer batches its cells into a few paths, one per colour, so even a
/// large maze costs only a few dozen fills per frame.
enum MazeRenderer {
    // MARK: Board

    /// The floor, walls and mud, plus the carving effects while a maze is generated.
    static func drawBoard(
        _ grid: MazeGrid,
        carving: MazeCarvingPlayback?,
        glowSteps: Double,
        layout: MazeLayout,
        in context: GraphicsContext
    ) {
        guard grid.width == layout.columns, grid.height == layout.rows else { return }
        let board = layout.boardRect
        context.fill(Path(board), with: .color(MazePalette.floor))

        var walls = Path()
        var litEdges = Path()
        var shadedEdges = Path()
        var mud = Path()
        var flecks = Path()
        let lip = max(layout.cellSize * 0.12, 0.5)
        let width = grid.width
        let cells = grid.cells
        for index in cells.indices {
            switch cells[index] {
            case .wall:
                let rect = layout.rect(index: index)
                walls.addRect(rect)
                // Walls are lit from above: a bright lip where floor lies above, a dark one where it lies below.
                if index >= width, cells[index - width] != .wall {
                    litEdges.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: lip))
                }
                if index + width < cells.count, cells[index + width] != .wall {
                    shadedEdges.addRect(CGRect(x: rect.minX, y: rect.maxY - lip, width: rect.width, height: lip))
                }
            case .mud:
                let rect = layout.rect(index: index)
                mud.addRect(rect)
                addFlecks(forCell: index, in: rect, to: &flecks)
            case .open:
                break
            }
        }

        let wallShading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [MazePalette.wallTop, MazePalette.wallBottom]),
            startPoint: CGPoint(x: board.midX, y: board.minY),
            endPoint: CGPoint(x: board.midX, y: board.maxY)
        )
        context.fill(walls, with: wallShading)
        context.fill(litEdges, with: .color(MazePalette.wallHighlight))
        context.fill(shadedEdges, with: .color(MazePalette.wallShadow))
        context.fill(mud, with: .color(MazePalette.mud))
        context.fill(flecks, with: .color(MazePalette.mudFleck))

        if let carving {
            drawCarving(carving, glowSteps: glowSteps, layout: layout, in: context)
        }
    }

    /// A slim line through the marked cells: a square at each cell's centre,
    /// bridged to marked neighbours east and south. In a block maze, marked
    /// neighbours are always consecutive in the generator's stack or walk, so
    /// the bridges trace it exactly. `thickness` is a fraction of a cell.
    private static func thread(through marked: [Bool], thickness: CGFloat, layout: MazeLayout) -> Path {
        var path = Path()
        let columns = layout.columns
        let size = layout.cellSize
        let inset = size * (1 - thickness) / 2
        let width = size * thickness
        for index in marked.indices where marked[index] {
            let cell = layout.rect(index: index)
            path.addRect(cell.insetBy(dx: inset, dy: inset))
            let column = index % columns
            if column + 1 < columns, marked[index + 1] {
                path.addRect(CGRect(x: cell.midX, y: cell.minY + inset, width: size, height: width))
            }
            if index + columns < marked.count, marked[index + columns] {
                path.addRect(CGRect(x: cell.minX + inset, y: cell.midY, width: width, height: size))
            }
        }
        return path
    }

    /// Scatters three flecks over a mud cell. Their positions are hashed from
    /// the cell's index, so they stay put from frame to frame.
    private static func addFlecks(forCell index: Int, in rect: CGRect, to path: inout Path) {
        var hash = (UInt64(truncatingIfNeeded: index) &+ 0x632B_E59B_D9B4_E019) &* 0x9E37_79B9_7F4A_7C15
        let radius = max(rect.width * 0.075, 0.6)
        for _ in 0..<3 {
            hash = (hash ^ (hash >> 29)) &* 0xBF58_476D_1CE4_E5B9
            let u = CGFloat(hash & 0xFFFF) / 65_535
            let v = CGFloat((hash >> 16) & 0xFFFF) / 65_535
            let x = rect.minX + rect.width * (0.2 + 0.6 * u)
            let y = rect.minY + rect.height * (0.2 + 0.6 * v)
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
        }
    }

    /// Fresh cells flash and fade, the working set glows violet, and a soft
    /// light follows the generator's hand.
    private static func drawCarving(
        _ carving: MazeCarvingPlayback,
        glowSteps: Double,
        layout: MazeLayout,
        in context: GraphicsContext
    ) {
        let steps = carving.generation.steps
        let applied = carving.applied
        let window = max(Int(glowSteps.rounded()), 1)

        // One path per terrain per age band. MazeCell's raw values (wall, open, mud) index the tints.
        let bands = 5
        let tints = [MazePalette.wallGlow, MazePalette.carveGlow, MazePalette.mudGlow]
        var glows = Array(repeating: Path(), count: bands * tints.count)
        for index in max(applied - window, 0)..<applied {
            guard case let .set(point, terrain) = steps[index] else { continue }
            let age = Double(applied - 1 - index) / Double(window)
            let band = min(Int(age * Double(bands)), bands - 1)
            glows[Int(terrain.rawValue) * bands + band].addRect(layout.rect(of: point))
        }
        for (slot, path) in glows.enumerated() where !path.isEmpty {
            let fade = 1 - Double(slot % bands) / Double(bands)
            context.fill(path, with: .color(tints[slot / bands].opacity(0.5 * fade)))
        }

        if carving.markedCount > 0 {
            let marked = carving.marked
            context.fill(
                thread(through: marked, thickness: 0.78, layout: layout),
                with: .color(MazePalette.working.opacity(0.22))
            )
            context.fill(
                thread(through: marked, thickness: 0.36, layout: layout),
                with: .color(MazePalette.working.opacity(0.95))
            )
        }

        if let head = carving.head, !carving.isFinished {
            let center = layout.center(of: head)
            let radius = max(layout.cellSize * 1.6, 8)
            let light = Gradient(colors: [
                Color.white.opacity(0.85), MazePalette.carveGlow.opacity(0.35), MazePalette.carveGlow.opacity(0),
            ])
            context.fill(
                circle(center, radius),
                with: .radialGradient(light, center: center, startRadius: 0, endRadius: radius)
            )
        }
    }

    // MARK: Search

    /// The explored region coloured by expansion order, the latest expansions
    /// flaring white, and the frontier as bright beads.
    static func drawSearch(
        _ search: MazeSearchPlayback,
        grid: MazeGrid,
        flareSteps: Double,
        layout: MazeLayout,
        in context: GraphicsContext
    ) {
        guard grid.width == layout.columns, grid.height == layout.rows else { return }
        let timeline = search.timeline
        let step = search.step

        var shades = Array(repeating: Path(), count: MazePalette.searchShades.count)
        var wadedMud = Path()
        var wadedFlecks = Path()
        for position in 0..<step {
            let cell = Int(timeline.expansionOrder[position])
            let rect = layout.rect(index: cell)
            shades[Int(search.shades[position])].addRect(rect)
            if grid.cells[cell] == .mud {
                wadedMud.addRect(rect)
                addFlecks(forCell: cell, in: rect, to: &wadedFlecks)
            }
        }
        for (shade, path) in shades.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(MazePalette.searchShades[shade]))
        }
        // Explored mud keeps its earthy tint and texture, so detours around it stay legible.
        context.fill(wadedMud, with: .color(MazePalette.mud.opacity(0.6)))
        context.fill(wadedFlecks, with: .color(MazePalette.mudFleck.opacity(0.8)))

        if !search.isFinished {
            let window = max(Int(flareSteps.rounded()), 1)
            let bands = 4
            var flares = Array(repeating: Path(), count: bands)
            for position in max(step - window, 0)..<step {
                let age = Double(step - 1 - position) / Double(window)
                let band = min(Int(age * Double(bands)), bands - 1)
                flares[band].addRect(layout.rect(index: Int(timeline.expansionOrder[position])))
            }
            for (band, path) in flares.enumerated() where !path.isEmpty {
                let fade = 1 - Double(band) / Double(bands)
                context.fill(path, with: .color(MazePalette.flare.opacity(0.55 * fade)))
            }
        }

        var forwardBeads = Path()
        var goalBeads = Path()
        let inset = layout.cellSize * 0.18
        let corner = CGSize(width: layout.cellSize * 0.2, height: layout.cellSize * 0.2)
        let discovered = timeline.discoveryCount(atStep: step)
        for position in 0..<discovered {
            let cell = Int(timeline.discoveryOrder[position])
            guard !timeline.isExpanded(cell, atStep: step) else { continue }
            let bead = layout.rect(index: cell).insetBy(dx: inset, dy: inset)
            if timeline.discoveryFromGoal[position] {
                goalBeads.addRoundedRect(in: bead, cornerSize: corner)
            } else {
                forwardBeads.addRoundedRect(in: bead, cornerSize: corner)
            }
        }
        if !search.isFinished {
            // A halo makes the advancing frontier shimmer against the explored region.
            let halo = max(layout.cellSize * 0.3, 1)
            context.stroke(forwardBeads, with: .color(MazePalette.frontier.opacity(0.25)), lineWidth: halo)
            context.stroke(goalBeads, with: .color(MazePalette.goalFrontier.opacity(0.25)), lineWidth: halo)
        }
        context.fill(forwardBeads, with: .color(MazePalette.frontier))
        context.fill(goalBeads, with: .color(MazePalette.goalFrontier))
    }

    // MARK: Overlay

    /// The route: a thick, glowing, round-capped line that draws itself in.
    /// Once drawn, a spark runs along it from start to goal every few seconds.
    static func drawRoute(
        _ route: [MazePoint],
        reveal: Double,
        time: TimeInterval,
        layout: MazeLayout,
        in context: GraphicsContext
    ) {
        guard route.count > 1, reveal > 0 else { return }
        var line = Path()
        line.move(to: layout.center(of: route[0]))
        for point in route.dropFirst() {
            line.addLine(to: layout.center(of: point))
        }
        let visible = reveal < 1 ? line.trimmedPath(from: 0, to: CGFloat(reveal)) : line
        let width = max(layout.cellSize * 0.34, 2.5)

        func stroke(_ path: Path, _ color: Color, _ lineWidth: CGFloat) {
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        stroke(visible, MazePalette.path.opacity(0.12), width * 3.4)
        stroke(visible, MazePalette.path.opacity(0.28), width * 2)
        stroke(visible, MazePalette.path, width)
        stroke(visible, MazePalette.pathCore.opacity(0.9), width * 0.36)

        guard reveal >= 1 else { return }
        let travel = min(Double(route.count) / 32, 3)
        let cycle = travel + 1.6
        let progress = time.truncatingRemainder(dividingBy: cycle) / travel
        guard progress < 1 else { return }
        let tail = min(0.35, 6 / Double(route.count))
        let spark = line.trimmedPath(from: CGFloat(max(progress - tail, 0)), to: CGFloat(progress))
        stroke(spark, Color.white.opacity(0.3), width * 1.7)
        stroke(spark, Color.white.opacity(0.95), width * 0.55)
    }

    /// A start or goal marker with a gently breathing body, a soft glow and a
    /// ring that swells and fades. The goal pulses half a beat after the start.
    static func drawEndpoint(
        _ endpoint: MazeEndpoint,
        at point: MazePoint,
        time: TimeInterval,
        emphasized: Bool,
        layout: MazeLayout,
        in context: GraphicsContext
    ) {
        let center = layout.center(of: point)
        // Markers never shrink below a comfortable target, even on large mazes.
        let size = max(layout.cellSize, 10)
        let color = endpoint == .start ? MazePalette.start : MazePalette.goal
        let beat = time / 1.8 + (endpoint == .start ? 0 : 0.5)
        let phase = beat - beat.rounded(.down)

        let ringRadius = size * CGFloat(0.42 + 0.7 * phase)
        context.stroke(
            circle(center, ringRadius),
            with: .color(color.opacity(0.75 * (1 - phase))),
            lineWidth: max(1.2, size * 0.07)
        )

        let glowRadius = size * 0.9
        context.fill(
            circle(center, glowRadius),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.5), color.opacity(0)]),
                center: center, startRadius: 0, endRadius: glowRadius
            )
        )
        // A dark disc seats the marker, so it stands out even where the route runs into it.
        context.fill(circle(center, size * 0.58), with: .color(MazePalette.floor.opacity(0.85)))

        let breath = 1 + 0.06 * CGFloat(sin(2 * Double.pi * phase))
        let radius = size * (emphasized ? 0.44 : 0.36) * breath
        let outline = Color.black.opacity(0.35)
        switch endpoint {
        case .start:
            context.fill(circle(center, radius), with: .color(color))
            context.stroke(circle(center, radius), with: .color(outline), lineWidth: 1)
            context.fill(circle(center, radius * 0.38), with: .color(Color.white.opacity(0.9)))
        case .goal:
            let reach = radius * 1.25
            var diamond = Path()
            diamond.move(to: CGPoint(x: center.x, y: center.y - reach))
            diamond.addLine(to: CGPoint(x: center.x + reach, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + reach))
            diamond.addLine(to: CGPoint(x: center.x - reach, y: center.y))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(color))
            context.stroke(diamond, with: .color(outline), lineWidth: 1)
            context.fill(circle(center, radius * 0.34), with: .color(Color.white.opacity(0.92)))
        }
    }

    /// The brush preview under the pointer. Over a marker it becomes a dashed
    /// ring, which says the marker can be dragged.
    static func drawBrush(
        at cell: MazePoint,
        tool: MazeTool,
        overEndpoint: Bool,
        layout: MazeLayout,
        in context: GraphicsContext
    ) {
        if overEndpoint {
            let radius = max(layout.cellSize, 10) * 0.72
            context.stroke(
                circle(layout.center(of: cell), radius),
                with: .color(Color.white.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
            )
            return
        }
        let rect = layout.rect(of: cell).insetBy(dx: 0.75, dy: 0.75)
        let outline = Path(roundedRect: rect, cornerRadius: min(layout.cellSize * 0.2, 4))
        let color = brushColor(for: tool)
        context.fill(outline, with: .color(color.opacity(0.22)))
        context.stroke(outline, with: .color(color.opacity(0.9)), lineWidth: 1.5)
    }

    private static func brushColor(for tool: MazeTool) -> Color {
        switch tool {
        case .wall: Color(white: 0.85)
        case .mud: MazePalette.mudGlow
        case .erase: Color.white
        case .start: MazePalette.start
        case .goal: MazePalette.goal
        }
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }
}
