import SortKit
import SwiftUI

/// The exhibit's control panel.
struct SortingControls: View {
    let model: SortingModel

    var body: some View {
        ControlSection("Algorithm") {
            SortingAlgorithmSection(model: model)
        }
        ControlSection("Playback") {
            SortingPlaybackSection(model: model)
        }
        ControlSection("Statistics") {
            SortingStatistics(model: model)
        }
        ControlSection("Input") {
            SortingInputSection(model: model)
        }
        ControlSection("Display") {
            SortingDisplaySection(model: model)
        }
        ControlSection("Sound") {
            SortingSoundSection(model: model)
        }
    }
}

// MARK: - Algorithm

private struct SortingAlgorithmSection: View {
    let model: SortingModel

    var body: some View {
        Picker("Mode", selection: Binding(get: { model.isRacing }, set: { model.setRacing($0) })) {
            Text("Solo").tag(false)
            Text("Race of Four").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if model.isRacing {
            ForEach(model.raceAlgorithms.indices, id: \.self) { lane in
                HStack(spacing: 8) {
                    Text("\(lane + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    SortingAlgorithmPicker(selection: Binding(
                        get: { model.raceAlgorithms[lane] },
                        set: { model.setRaceAlgorithm($0, lane: lane) }
                    ))
                }
            }
            Text("Every lane sorts the same array and advances the same number of steps each frame, so the fewest steps wins. Only lane 1 makes sound.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            SortingAlgorithmPicker(selection: Binding(get: { model.algorithm }, set: { model.select($0) }))
            SortingAlgorithmCard(algorithm: model.algorithm)
        }
    }
}

/// A menu of every algorithm, grouped by family.
private struct SortingAlgorithmPicker: View {
    @Binding var selection: SortAlgorithm

    var body: some View {
        Picker("Algorithm", selection: $selection) {
            ForEach(SortFamily.allCases) { family in
                Section(family.name) {
                    ForEach(family.algorithms) { algorithm in
                        Text(algorithm.name).tag(algorithm)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}

/// What the selected algorithm does and what it costs.
private struct SortingAlgorithmCard: View {
    let algorithm: SortAlgorithm

    var body: some View {
        let complexity = algorithm.complexity

        Text(algorithm.summary)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                header("Best")
                header("Average")
                header("Worst")
                header("Memory")
            }
            GridRow {
                cost(complexity.best)
                cost(complexity.average, growth: complexity.averageGrowth)
                cost(complexity.worst)
                cost(complexity.memory)
            }
        }

        HStack(spacing: 6) {
            SortingBadge(
                algorithm.isStable ? "Stable" : "Unstable",
                symbol: algorithm.isStable ? "equal.circle.fill" : "arrow.left.arrow.right.circle.fill",
                tint: algorithm.isStable ? .green : .orange
            )
            .help(algorithm.isStable
                ? "Equal values keep their original order."
                : "Equal values may come out in a different order.")
            SortingBadge(
                algorithm.isInPlace ? "In place" : "Extra memory",
                symbol: algorithm.isInPlace ? "square.stack.fill" : "square.stack.3d.up.fill",
                tint: algorithm.isInPlace ? .blue : .purple
            )
            .help(algorithm.isInPlace
                ? "Needs no buffer proportional to the input."
                : "Uses a buffer as large as the input.")
            if !algorithm.isComparisonSort {
                SortingBadge("No compares", symbol: "number.circle.fill", tint: .teal)
                    .help("Orders values by their digits instead of comparing them.")
            }
        }

        if let note = complexity.note {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
    }

    private func cost(_ text: String, growth: SortGrowth? = nil) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, growth == nil ? 0 : 5)
            .padding(.vertical, growth == nil ? 0 : 1)
            .background {
                if let growth {
                    Capsule().fill(Self.color(for: growth).opacity(0.2))
                }
            }
    }

    private static func color(for growth: SortGrowth) -> Color {
        switch growth {
        case .linear: .green
        case .linearithmic: .teal
        case .subquadratic: .yellow
        case .quadratic: .red
        }
    }
}

/// A small tinted capsule with an icon.
private struct SortingBadge: View {
    let title: String
    let symbol: String
    let tint: Color

    init(_ title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Playback

private struct SortingPlaybackSection: View {
    let model: SortingModel

    var body: some View {
        HStack(spacing: 8) {
            SortingPlayButton(model: model)

            Button {
                model.step()
            } label: {
                Label("Step", systemImage: "forward.frame.fill")
            }
            .buttonStyle(.bordered)
            .help("Apply one operation (→)")
        }
        .controlSize(.large)

        HStack(spacing: 8) {
            Button {
                model.reset()
            } label: {
                Label("Reset", systemImage: "backward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            .help("Rewind to the same unsorted array")

            Button {
                model.shuffle()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .help("Deal a new array (R)")
        }
        .buttonStyle(.bordered)

        ParameterSlider("Speed", value: speedExponent, in: 0...log10(SortingModel.speedRange.upperBound)) { exponent in
            let speed = pow(10, exponent)
            return speed < 1_000 ? "\(Int(speed.rounded())) steps/s" : "\(compactCount(speed)) steps/s"
        }
    }

    /// Speed on a logarithmic scale, from 1 to 50,000 steps a second.
    private var speedExponent: Binding<Double> {
        Binding(
            get: { log10(model.speed) },
            set: { model.speed = pow(10, $0) }
        )
    }
}

/// Play, Pause, Resume or Sort Again. A leaf view, because its title
/// depends on the lanes, which change every frame.
private struct SortingPlayButton: View {
    let model: SortingModel

    var body: some View {
        Button {
            model.togglePlay()
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.92, green: 0.49, blue: 0.1))
        .help("Play or pause (Space)")
    }

    private var title: String {
        if model.isPlaying { return "Pause" }
        if model.isFinished { return "Sort Again" }
        return model.hasStarted ? "Resume" : "Play"
    }

    private var symbol: String {
        if model.isPlaying { return "pause.fill" }
        return model.isFinished ? "arrow.clockwise" : "play.fill"
    }
}

// MARK: - Statistics

private struct SortingStatistics: View {
    let model: SortingModel

    var body: some View {
        if model.isRacing {
            ForEach(model.lanes) { lane in
                StatRow(lane.algorithm.name, raceSummary(for: lane))
            }
        } else if let lane = model.primaryLane {
            let counts = lane.counts
            StatRow("Comparisons", counts.comparisons.formatted())
            StatRow("Swaps", counts.swaps.formatted())
            StatRow("Writes", counts.writes.formatted())
            if lane.algorithm == .radixLSD || lane.algorithm == .merge {
                StatRow("Reads", counts.reads.formatted())
            }
            if let total = lane.totalSteps {
                StatRow("Steps", "\(counts.steps.formatted()) of \(total.formatted())")
                StatRow("Progress", "\(Int((lane.progress * 100).rounded(.down)))%")
            } else {
                StatRow("Steps", "Tracing…")
            }
        }
    }

    private func raceSummary(for lane: SortingLane) -> String {
        let steps = lane.counts.steps.formatted()
        guard let place = model.place(of: lane) else { return steps }
        let ordinal = [1: "1st", 2: "2nd", 3: "3rd"][place] ?? "\(place)th"
        return "\(steps) · \(ordinal)"
    }
}

// MARK: - Input

private struct SortingInputSection: View {
    let model: SortingModel

    var body: some View {
        SortingInputPicker(selection: Binding(get: { model.input }, set: { model.select($0) }))

        // log₂ of 8 and 1,024.
        ParameterSlider("Bars", value: sizeExponent, in: 3...10) { exponent in
            "\(Int(pow(2, exponent).rounded()))"
        }

        SortingSlowSortWarning(model: model)
    }

    /// Bar count on a logarithmic scale, from 8 to 1,024.
    private var sizeExponent: Binding<Double> {
        Binding(
            get: { log2(Double(model.size)) },
            set: { model.setSize(Int(pow(2, $0).rounded())) }
        )
    }
}

/// Quadratic sorts on big arrays take a while even at full speed. The count
/// is exact: it comes from the prepared traces.
private struct SortingSlowSortWarning: View {
    let model: SortingModel

    var body: some View {
        if let steps = model.lanes.compactMap(\.totalSteps).max(), steps >= 100_000 {
            let seconds = Int((Double(steps) / SortingModel.speedRange.upperBound).rounded())
            Label("\(compactCount(Double(steps))) steps: about \(seconds) s even at top speed.", systemImage: "tortoise.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Five tiles, each a thumbnail of its input shape.
private struct SortingInputPicker: View {
    @Binding var selection: SortInput

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(SortInput.allCases) { input in
                    Button {
                        selection = input
                    } label: {
                        SortingInputTile(input: input, isSelected: input == selection)
                    }
                    .buttonStyle(.plain)
                    .help(input.name)
                    .accessibilityLabel(input.name)
                    .accessibilityAddTraits(input == selection ? .isSelected : [])
                }
            }
            Text(selection.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SortingInputTile: View {
    let input: SortInput
    let isSelected: Bool

    var body: some View {
        let values = input.generate(count: 14, seed: 7)
        Canvas { context, size in
            let pitch = size.width / CGFloat(values.count)
            let span = Double(max(1, values.count - 1))
            for (index, value) in values.enumerated() {
                let level = Double(value - 1) / span
                let height = size.height * CGFloat(0.12 + 0.88 * level)
                let rect = CGRect(
                    x: CGFloat(index) * pitch + pitch * 0.12,
                    y: size.height - height,
                    width: pitch * 0.76,
                    height: height
                )
                let color = SortingPalette.rainbow[SortingPalette.bucket(for: level)]
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Exhibit.sorting.tint.opacity(0.16) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Exhibit.sorting.tint : Color.primary.opacity(0.1),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Display and sound

private struct SortingDisplaySection: View {
    let model: SortingModel

    var body: some View {
        @Bindable var model = model
        Picker("Style", selection: $model.style) {
            ForEach(SortingStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text(model.style == .bars
            ? "Height and hue show each value."
            : "Each value is a dot at (index, value); sorting pulls the cloud onto the diagonal.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SortingSoundSection: View {
    let model: SortingModel

    var body: some View {
        HStack {
            Text("Sonify every access")
            Spacer(minLength: 8)
            Toggle("Sound", isOn: Binding(get: { model.isSoundOn }, set: { model.setSoundOn($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .font(.callout)

        ParameterSlider("Volume", value: Binding(get: { model.volume }, set: { model.setVolume($0) }), in: 0...1) {
            "\(Int(($0 * 100).rounded()))%"
        }
        .disabled(!model.isSoundOn)

        Text("Pitch rises with the value touched, from 120 Hz to 1.5 kHz, and pans with its position. Comparisons sound soft, moves bright.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
