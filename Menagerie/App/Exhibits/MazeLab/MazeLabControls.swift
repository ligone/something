import MazeKit
import SwiftUI

/// Choosing, sizing and finishing a maze.
struct MazeGenerateSection: View {
    @Bindable var model: MazeLabModel

    var body: some View {
        ControlSection("Maze") {
            Picker("Generator", selection: $model.generator) {
                ForEach(MazeGenerator.allCases) { generator in
                    Text(generator.name).tag(generator)
                }
            }
            MazeCaption(model.generator.summary)
            Picker("Size", selection: $model.size) {
                ForEach(MazeSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            ParameterSlider("Loops", value: $model.loops, in: 0...1, format: { "\(Int(($0 * 100).rounded()))%" })
                .help("The share of dead ends knocked through. Each one adds a loop, so searches have routes to choose between.")
            Toggle("Mud patches", isOn: $model.mudEnabled)
                .help("Mud is passable but costs \(MazeCell.mudCost) per step instead of 1.")
            Button {
                model.generate()
            } label: {
                Label("Generate", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help("Carve another maze with the same settings and a fresh random seed")
            StatRow("Open cells", model.topology?.passableCells.formatted() ?? "—")
            StatRow("Dead ends", model.topology?.deadEnds.formatted() ?? "—")
            StatRow("Loops", model.topology?.loops.formatted() ?? "—")
        }
    }
}

/// Choosing a solver and controlling playback.
struct MazeSearchSection: View {
    @Bindable var model: MazeLabModel

    var body: some View {
        let solver = model.solver
        // Rates scale with the maze, so the speed label quotes the current maze's rate.
        let sizeFactor = Double(model.columns * model.rows) / MazePlaybackSpeed.referenceCells
        ControlSection("Search") {
            Picker("Solver", selection: $model.solver) {
                ForEach(MazeSolver.allCases) { option in
                    Text(option.name).tag(option)
                }
            }
            MazeCaption(solver.summary)
            HStack(spacing: 6) {
                if solver.isOptimal {
                    TagChip(text: solver.respectsTerrainCost ? "Cheapest path" : "Fewest steps", tint: .green)
                } else {
                    TagChip(text: "No guarantee", tint: .orange)
                }
                TagChip(text: solver.respectsTerrainCost ? "Weighs mud" : "Ignores mud", tint: solver.respectsTerrainCost ? .brown : .gray)
            }
            ParameterSlider("Speed", value: $model.speed, in: 0...1, format: { slider in
                MazePlaybackSpeed.label(stepsPerSecond: MazePlaybackSpeed.stepsPerSecond(slider: slider) * sizeFactor)
            })
            HStack(spacing: 8) {
                Button {
                    model.solve()
                } label: {
                    Label("Solve", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .help("Run the solver again, animated")
                Button {
                    model.togglePause()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .disabled(model.activity == .idle)
                .help(model.isPaused ? "Resume" : "Pause")
                Button {
                    model.skipAhead()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(model.activity == .idle)
                .help("Finish instantly")
            }
            MazeExpansionLegend()
        }
    }
}

/// The painting tools.
struct MazePaintSection: View {
    @Bindable var model: MazeLabModel

    var body: some View {
        ControlSection("Paint") {
            MazeToolPalette(selection: $model.tool)
            MazeCaption(model.tool.help)
        }
    }
}

/// Every solver side by side on the current maze.
struct MazeCompareSection: View {
    let model: MazeLabModel

    var body: some View {
        ControlSection("Compare") {
            if let rows = model.comparison {
                MazeComparisonChart(rows: rows, highlighted: model.solver)
                MazeComparisonTable(rows: rows, highlighted: model.solver)
                MazeCaption("The comparison stays live: paint the maze and watch it change.")
                Button("Hide Comparison") {
                    model.hideComparison()
                }
                .controlSize(.small)
            } else {
                MazeCaption("Run all six solvers on this maze and compare their work.")
                Button {
                    model.compareAll()
                } label: {
                    Label("Compare All", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// A segmented palette of painting tools, with icons.
private struct MazeToolPalette: View {
    @Binding var selection: MazeTool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MazeTool.allCases) { tool in
                let isSelected = tool == selection
                Button {
                    selection = tool
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(height: 16)
                        Text(tool.title)
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Exhibit.mazeLab.tint.opacity(0.22) : Color.primary.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isSelected ? Exhibit.mazeLab.tint : Color.primary.opacity(0.1), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.help)
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The key to the explored region's colours.
private struct MazeExpansionLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LinearGradient(gradient: MazePalette.expansionGradient, startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .clipShape(Capsule())
            HStack {
                Text("First expanded")
                Spacer()
                Text("Last")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Secondary explanatory text that wraps.
private struct MazeCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
