import AppKit
import LifeKit
import SwiftUI

/// The attraction matrix as a grid: row species down the left, column species
/// across the top.
///
/// Each cell shows how the row's species responds to the column's: a green bar
/// rising from the middle for a pull, a red bar falling for a push. Drag a cell
/// up or down to change it, click to swap attraction and repulsion, or
/// Option-click to clear it. Hovering shows the exact value and the force
/// curve the pair will feel.
struct SpeciesMatrixEditor: View {
    let model: ParticleLifeModel

    @State private var hovered: MatrixCell?
    @State private var edit: CellEdit?

    private static let gap: CGFloat = 3
    private static let headerSize: CGFloat = 16
    /// Dragging this far changes a value by 1, so the whole range spans 180 points.
    private static let pointsPerUnit: CGFloat = 90

    private var matrix: SpeciesMatrix { model.matrix }
    private var count: Int { matrix.speciesCount }

    /// Cells shrink as species are added, keeping the grid about 230 points wide.
    private var cellSize: CGFloat {
        let available = 213 - Self.gap * CGFloat(count - 1)
        return min(40, (available / CGFloat(count)).rounded(.down))
    }

    /// The cell being dragged, or else the one under the pointer.
    private var focus: MatrixCell? {
        guard let cell = edit?.cell ?? hovered, cell.row < count, cell.column < count else { return nil }
        return cell
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            grid
                .animation(edit == nil ? .easeOut(duration: 0.25) : nil, value: matrix)
            MatrixReadout(
                cell: focus,
                value: focus.map { matrix[$0.row, $0.column] } ?? 0,
                repulsionRadius: model.rules.repulsionRadius
            )
        }
    }

    // MARK: - Grid

    private var grid: some View {
        let size = cellSize
        return VStack(alignment: .leading, spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                Color.clear
                    .frame(width: Self.headerSize, height: Self.headerSize)
                ForEach(0..<count, id: \.self) { column in
                    SpeciesDot(species: column, isHighlighted: focus?.column == column)
                        .frame(width: size, height: Self.headerSize)
                }
            }
            HStack(alignment: .top, spacing: Self.gap) {
                VStack(spacing: Self.gap) {
                    ForEach(0..<count, id: \.self) { row in
                        SpeciesDot(species: row, isHighlighted: focus?.row == row)
                            .frame(width: Self.headerSize, height: size)
                    }
                }
                cells(size: size)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cells(size: CGFloat) -> some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<count, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(0..<count, id: \.self) { column in
                        cellView(row: row, column: column, size: size)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            if case .active(let location) = phase {
                hovered = matrixCell(at: location, size: size)
                NSCursor.resizeUpDown.set()
            } else {
                hovered = nil
                NSCursor.arrow.set()
            }
        }
        .gesture(editGesture(size: size))
    }

    private func cellView(row: Int, column: Int, size: CGFloat) -> some View {
        let value = attraction(row: row, column: column)
        let cell = MatrixCell(row: row, column: column)
        let isFocused = focus == cell
        let isMirror = model.isSymmetric && row != column && focus == cell.mirrored
        return MatrixCellView(value: value, size: size, isFocused: isFocused, isMirror: isMirror)
            .accessibilityElement()
            .accessibilityLabel("\(SpeciesPalette.name(row)) toward \(SpeciesPalette.name(column))")
            .accessibilityValue(MatrixReadout.describe(value))
            .accessibilityAdjustableAction { direction in
                let step: Float = direction == .increment ? 0.1 : -0.1
                model.setAttraction(attraction(row: row, column: column) + step, row: row, column: column)
            }
    }

    /// The matrix entry, or 0 for a cell that is on its way out. When the
    /// species count drops, SwiftUI can re-render a ForEach child for the old,
    /// larger grid before it removes that child, so its row or column may no
    /// longer exist.
    private func attraction(row: Int, column: Int) -> Float {
        guard row < count, column < count else { return 0 }
        return matrix[row, column]
    }

    /// The cell under a point in the grid's own coordinates. Points in the
    /// gutters count toward the cell above and to the left.
    private func matrixCell(at point: CGPoint, size: CGFloat) -> MatrixCell? {
        let pitch = size + Self.gap
        guard point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / pitch)
        let row = Int(point.y / pitch)
        guard row < count, column < count else { return nil }
        return MatrixCell(row: row, column: column)
    }

    // MARK: - Editing

    private func editGesture(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { drag in
                if edit == nil {
                    guard let cell = matrixCell(at: drag.startLocation, size: size) else { return }
                    edit = CellEdit(cell: cell, startValue: matrix[cell.row, cell.column])
                }
                guard var current = edit else { return }
                // Ignore the jitter of an ordinary click.
                if !current.hasMoved && abs(drag.translation.height) < 3 { return }
                current.hasMoved = true
                edit = current
                let dragged = current.startValue - Float(drag.translation.height / Self.pointsPerUnit)
                model.setAttraction(Self.snapped(dragged), row: current.cell.row, column: current.cell.column)
            }
            .onEnded { _ in
                defer { edit = nil }
                guard let current = edit, !current.hasMoved,
                      current.cell.row < count, current.cell.column < count else { return }
                // A click: swap attraction and repulsion, or clear with Option.
                let value = matrix[current.cell.row, current.cell.column]
                let cleared = NSEvent.modifierFlags.contains(.option)
                model.setAttraction(cleared ? 0 : -value, row: current.cell.row, column: current.cell.column)
            }
    }

    /// Rounds to hundredths and makes zero slightly sticky, so it is easy to hit.
    private static func snapped(_ value: Float) -> Float {
        let clamped = min(max(value, -1), 1)
        if abs(clamped) < 0.04 { return 0 }
        return (clamped * 100).rounded() / 100
    }
}

/// A position in the matrix.
private struct MatrixCell: Hashable {
    let row: Int
    let column: Int

    /// The entry across the diagonal, which a symmetric matrix keeps equal.
    var mirrored: MatrixCell { MatrixCell(row: column, column: row) }
}

/// A drag in progress on one cell.
private struct CellEdit {
    let cell: MatrixCell
    let startValue: Float
    var hasMoved = false
}

/// One matrix entry: a tinted tile with a bar that rises for attraction and
/// falls for repulsion.
private struct MatrixCellView: View {
    let value: Float
    let size: CGFloat
    let isFocused: Bool
    let isMirror: Bool

    var body: some View {
        let magnitude = CGFloat(min(abs(value), 1))
        let tint = InteractionPalette.color(for: value)
        let bar = magnitude * (size / 2 - 3)
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint.opacity(Double(0.06 + 0.3 * magnitude)))
            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: size - 8, height: 1)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint.opacity(Double(0.6 + 0.4 * magnitude)))
                .frame(width: size - 10, height: max(bar, 0.5))
                .offset(y: value >= 0 ? -bar / 2 : bar / 2)
                .opacity(value == 0 ? 0 : 1)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(isFocused ? 0.85 : 0), lineWidth: 1.5)
            if isMirror {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A glowing dot in a species' color, used as a matrix header and legend.
private struct SpeciesDot: View {
    let species: Int
    var isHighlighted = false

    var body: some View {
        let color = SpeciesPalette.color(species)
        Circle()
            .fill(color)
            .frame(width: isHighlighted ? 11 : 8, height: isHighlighted ? 11 : 8)
            .shadow(color: color.opacity(isHighlighted ? 0.9 : 0.5), radius: isHighlighted ? 4 : 2)
            .animation(.easeOut(duration: 0.15), value: isHighlighted)
            .accessibilityHidden(true)
    }
}

/// The line under the grid: details of the focused cell, or a short legend.
/// Its height is fixed so hovering never shifts the controls below.
private struct MatrixReadout: View {
    let cell: MatrixCell?
    let value: Float
    let repulsionRadius: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cell {
                HStack(spacing: 5) {
                    SpeciesDot(species: cell.row)
                    Text(SpeciesPalette.name(cell.row))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SpeciesDot(species: cell.column)
                    Text(SpeciesPalette.name(cell.column))
                    Spacer(minLength: 4)
                    Text(Self.verb(value))
                        .foregroundStyle(.secondary)
                    Text(Self.describe(value))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .foregroundStyle(value == 0 ? Color.secondary : InteractionPalette.color(for: value))
                }
                .font(.callout)
                ForceCurve(attraction: value, repulsionRadius: repulsionRadius)
                    .frame(height: 44)
            } else {
                Text("Each cell is how the row's species feels about the column's: green pulls, red pushes. Drag a cell up or down to change it, click to flip it, or ⌥-click to clear it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .topLeading)
    }

    static func describe(_ value: Float) -> String {
        String(format: "%+.2f", value)
    }

    static func verb(_ value: Float) -> String {
        value > 0 ? "pulls" : (value < 0 ? "pushes" : "ignores")
    }
}

/// The force one particle feels from another as their distance grows: the
/// universal repulsion up close, then a bump whose height is the matrix entry.
private struct ForceCurve: View {
    let attraction: Float
    let repulsionRadius: Float

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 2
            let width = size.width - inset * 2
            let middle = size.height / 2
            let amplitude = middle - inset
            let reach: Float = 1.12

            func point(at distance: Float) -> CGPoint {
                let force = LifeRules.force(atDistance: distance, attraction: attraction, repulsionRadius: repulsionRadius)
                let x = inset + CGFloat(distance / reach) * width
                return CGPoint(x: x, y: middle - CGFloat(force) * amplitude)
            }

            var curve = Path()
            let samples = 112
            for index in 0...samples {
                let location = point(at: reach * Float(index) / Float(samples))
                if index == 0 {
                    curve.move(to: location)
                } else {
                    curve.addLine(to: location)
                }
            }

            // Shade the area between the curve and the axis: green where it
            // pulls, red where it pushes.
            var area = curve
            area.addLine(to: CGPoint(x: inset + width, y: middle))
            area.addLine(to: CGPoint(x: inset, y: middle))
            area.closeSubpath()
            var pulling = context
            pulling.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: middle)))
            pulling.fill(area, with: .color(InteractionPalette.attraction.opacity(0.3)))
            var pushing = context
            pushing.clip(to: Path(CGRect(x: 0, y: middle, width: size.width, height: size.height - middle)))
            pushing.fill(area, with: .color(InteractionPalette.repulsion.opacity(0.3)))

            var axis = Path()
            axis.move(to: CGPoint(x: inset, y: middle))
            axis.addLine(to: CGPoint(x: inset + width, y: middle))
            context.stroke(axis, with: .color(Color.primary.opacity(0.25)), lineWidth: 1)
            for marker in [repulsionRadius, 1] {
                let x = inset + CGFloat(marker / reach) * width
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: inset))
                tick.addLine(to: CGPoint(x: x, y: size.height - inset))
                context.stroke(tick, with: .color(Color.primary.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            context.stroke(curve, with: .color(Color.primary.opacity(0.8)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

/// Colors for attraction and repulsion in the matrix editor.
private enum InteractionPalette {
    static let attraction = Color(red: 0.26, green: 0.80, blue: 0.46)
    static let repulsion = Color(red: 0.98, green: 0.33, blue: 0.36)

    /// Green for a pull, red for a push.
    static func color(for value: Float) -> Color {
        value >= 0 ? attraction : repulsion
    }
}
