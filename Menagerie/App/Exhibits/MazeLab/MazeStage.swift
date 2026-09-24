import MazeKit
import SwiftUI

/// The maze stage: a shadowed plate, the board, the search, and an animated
/// overlay for the route and markers. Pressing or dragging paints with the
/// current tool, or moves the start or goal.
///
/// Each layer reads only the model state it draws. SwiftUI then redraws the
/// board only while a maze is carved or edited, and the search layer only
/// while a search plays or re-runs. Only the small overlay redraws every frame.
struct MazeStage: View {
    let model: MazeLabModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let area = MazeLayout.boardArea(in: proxy.size)
            let layout = MazeLayout(columns: model.columns, rows: model.rows, area: area, displayScale: displayScale)
            ZStack(alignment: .topLeading) {
                MazePlate(board: layout.boardRect)
                MazeBoardLayer(model: model, layout: layout)
                MazeSearchLayer(model: model, layout: layout)
                MazeOverlayLayer(model: model, layout: layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in model.pointerMoved(to: layout.cell(at: value.location)) }
                    .onEnded { _ in model.pointerReleased() }
            )
            .onContinuousHover { phase in
                let cell: MazePoint?
                switch phase {
                case let .active(location): cell = layout.cell(at: location)
                case .ended: cell = nil
                }
                if model.hoverCell != cell { model.hoverCell = cell }
            }
            .onChange(of: area.size, initial: true) { _, size in
                model.setBoardArea(size)
            }
        }
    }
}

/// The dark plate the board sits on. Its shadow lifts the maze off the stage.
private struct MazePlate: View {
    let board: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(MazePalette.floor)
            .frame(width: board.width, height: board.height)
            .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
            .offset(x: board.minX, y: board.minY)
    }
}

/// Floor, walls and mud, and the carving effects while a maze is generated.
private struct MazeBoardLayer: View {
    let model: MazeLabModel
    let layout: MazeLayout

    var body: some View {
        let grid = model.displayGrid
        let carving = model.carving
        // Fresh cells glow for a quarter of a second at any speed.
        let glowSteps = min(max(model.carvingStepsPerSecond * 0.25, 4), 1_500)
        Canvas { context, _ in
            MazeRenderer.drawBoard(grid, carving: carving, glowSteps: glowSteps, layout: layout, in: context)
        }
    }
}

/// The explored region and frontier of the latest search.
private struct MazeSearchLayer: View {
    let model: MazeLabModel
    let layout: MazeLayout

    var body: some View {
        if let search = model.search {
            let grid = model.grid
            let flareSteps = min(max(model.searchStepsPerSecond * 0.3, 2), 600)
            Canvas { context, _ in
                MazeRenderer.drawSearch(search, grid: grid, flareSteps: flareSteps, layout: layout, in: context)
            }
        }
    }
}

/// The route, the pulsing markers and the brush preview, redrawn every frame.
/// Its timeline also drives the model's playback.
private struct MazeOverlayLayer: View {
    let model: MazeLabModel
    let layout: MazeLayout

    var body: some View {
        TimelineView(.animation) { timeline in
            let date = timeline.date
            let grid = model.displayGrid
            let route = model.visibleRoute
            let reveal = model.routeReveal(at: date)
            // The border ring can't be painted, so no brush appears there.
            let hover = model.hoverCell.flatMap { cell in
                model.activity == .idle && !grid.isOnBorder(cell) ? cell : nil
            }
            let tool = model.tool
            Canvas { context, _ in
                let time = date.timeIntervalSinceReferenceDate
                MazeRenderer.drawRoute(route, reveal: reveal, time: time, layout: layout, in: context)
                if let hover {
                    let overEndpoint = hover == grid.start || hover == grid.goal
                    MazeRenderer.drawBrush(at: hover, tool: tool, overEndpoint: overEndpoint, layout: layout, in: context)
                }
                MazeRenderer.drawEndpoint(
                    .start, at: grid.start, time: time, emphasized: hover == grid.start, layout: layout, in: context
                )
                MazeRenderer.drawEndpoint(
                    .goal, at: grid.goal, time: time, emphasized: hover == grid.goal, layout: layout, in: context
                )
            }
            .onChange(of: date) { _, now in
                model.tick(at: now)
            }
        }
    }
}

/// Live statistics for the stage's heads-up display.
struct MazeHUD: View {
    let model: MazeLabModel

    var body: some View {
        HStack(spacing: 8) {
            if let carving = model.carving {
                StatPill(Self.title(for: carving.phase), carving.generation.generator.name)
                StatPill("Progress", "\(Int((carving.progress * 100).rounded()))%")
            } else if let search = model.search {
                let stats = search.trace.stats
                let solved = search.isFinished
                StatPill("Solver", search.trace.solver.name)
                StatPill("Expanded", search.step.formatted())
                StatPill("Path", solved ? (stats.foundGoal ? "\(stats.pathLength.formatted()) steps" : "Unreachable") : "…")
                StatPill("Cost", solved ? (stats.foundGoal ? stats.pathCost.formatted() : "—") : "…")
            }
        }
    }

    private static func title(for phase: MazeGeneration.Phase) -> String {
        switch phase {
        case .carving: "Carving"
        case .spreadingMud: "Spreading mud"
        case .braiding: "Braiding loops"
        }
    }
}
