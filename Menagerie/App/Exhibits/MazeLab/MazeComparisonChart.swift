import Charts
import MazeKit
import SwiftUI

/// Cells expanded by every solver on the current maze. The selected solver
/// is highlighted, the rest are grey, and each bar carries its value at the tip.
struct MazeComparisonChart: View {
    let rows: [MazeComparisonRow]
    let highlighted: MazeSolver
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let peak = max(rows.map(\.nodesExpanded).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("Cells expanded")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart(rows) { row in
                BarMark(
                    x: .value("Cells expanded", row.nodesExpanded),
                    y: .value("Solver", row.solver.shortName),
                    height: .fixed(14)
                )
                .cornerRadius(3)
                .foregroundStyle(row.solver == highlighted ? accent : muted)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text(row.nodesExpanded.formatted())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            // Headroom past the longest bar keeps its label inside the plot.
            .chartXScale(domain: 0...(peak + peak / 3))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: CGFloat(rows.count) * 22)
            .animation(.easeInOut(duration: 0.25), value: rows)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cells expanded by each solver")
    }

    /// The exhibit's green, one step darker in light mode so the bar keeps 3:1 contrast on white.
    private var accent: Color {
        colorScheme == .dark ? Exhibit.mazeLab.tint : Color(red: 0.20, green: 0.56, blue: 0.24)
    }

    private var muted: Color {
        Color.secondary.opacity(0.4)
    }
}

/// Path length and cost for every solver. A check marks the best value in each column.
struct MazeComparisonTable: View {
    let rows: [MazeComparisonRow]
    let highlighted: MazeSolver

    var body: some View {
        let solved = rows.filter(\.foundGoal)
        let fewestSteps = solved.map(\.pathLength).min()
        let lowestCost = solved.map(\.pathCost).min()
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Solver")
                Text("Steps")
                    .gridColumnAlignment(.trailing)
                Text("Cost")
                    .gridColumnAlignment(.trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(rows) { row in
                GridRow {
                    Text(row.solver.shortName)
                        .fontWeight(row.solver == highlighted ? .semibold : .regular)
                    value(row.foundGoal ? row.pathLength : nil, isBest: row.pathLength == fewestSteps)
                    value(row.foundGoal ? row.pathCost : nil, isBest: row.pathCost == lowestCost)
                }
                .font(.caption.monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private func value(_ number: Int?, isBest: Bool) -> some View {
        if let number {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(isBest ? 1 : 0)
                    .accessibilityHidden(true)
                Text(number.formatted())
            }
            .accessibilityLabel(isBest ? "\(number), best" : "\(number)")
        } else {
            Text("—")
                .foregroundStyle(.secondary)
                .accessibilityLabel("No path")
        }
    }
}
