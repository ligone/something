import ConnectFourKit
import SwiftUI

/// The control panel: the game, the engine, and the numbers behind Claude's
/// last move.
struct ConnectFourControls: View {
    @Bindable var model: ConnectFourModel

    var body: some View {
        ControlSection("Game") {
            gameControls
        }
        ControlSection("Engine") {
            engineControls
        }
        ControlSection(model.isThinking ? "Claude is thinking" : "Claude's last search") {
            searchStatistics
        }
    }

    // MARK: - Game

    private var gameControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled("Difficulty") {
                Picker("Difficulty", selection: $model.difficulty) {
                    ForEach(C4Difficulty.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.difficulty.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            labeled("First move") {
                Picker("First move", selection: $model.youMoveFirst) {
                    Text("You").tag(true)
                    Text("Claude").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(model.isDemo)

            Button {
                model.newGame()
            } label: {
                Label("New Game", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Exhibit.connectFour.tint)

            HStack(spacing: 8) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canUndo)
                .help("Take back your last move and Claude's reply. Shortcut: U")

                Button {
                    model.showHint()
                } label: {
                    Label("Hint", systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canHint)
                .help("Show the engine's best move for you. Shortcut: H")
            }
        }
    }

    // MARK: - Engine

    private var engineControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show engine analysis", isOn: $model.showsAnalysis)
                .toggleStyle(.switch)
            Toggle("Watch Claude play itself", isOn: $model.isDemo)
                .toggleStyle(.switch)
            if model.isDemo {
                ParameterSlider(
                    "Pause between moves",
                    value: $model.demoPause,
                    in: 0.2...2.0,
                    step: 0.1,
                    format: { String(format: "%.1f s", $0) }
                )
            }
            Text("The chips over the board score each column for the player to move. Dashed rings mark empty cells that would complete a four.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Statistics

    private var searchStatistics: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatRow("Nodes searched", statistics.nodes)
            StatRow("Depth reached", statistics.depth)
            StatRow("Time", statistics.time)
            StatRow("Speed", statistics.speed)
            if let verdict {
                Text(verdict)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if model.record.total > 0 {
                let record = model.record
                StatRow("Your record", "\(record.wins) won · \(record.losses) lost · \(record.draws) drawn")
            }
        }
    }

    /// Live numbers while Claude thinks, otherwise those of its last move.
    private var statistics: (nodes: String, depth: String, time: String, speed: String) {
        if model.isThinking {
            let speed = model.liveElapsed > 0 ? Double(model.liveNodes) / model.liveElapsed : 0
            return (
                ConnectFourFormat.count(model.liveNodes),
                "\(model.searchingDepth) plies…",
                ConnectFourFormat.seconds(model.liveElapsed),
                ConnectFourFormat.count(Int(speed)) + "/s"
            )
        }
        guard let analysis = model.lastDecision?.analysis else {
            return ("—", "—", "—", "—")
        }
        return (
            ConnectFourFormat.count(analysis.nodes),
            "\(analysis.depth) plies" + (analysis.isSolved ? ", solved" : ""),
            ConnectFourFormat.seconds(analysis.elapsed),
            ConnectFourFormat.count(Int(analysis.nodesPerSecond)) + "/s"
        )
    }

    /// While Claude thinks, its current favorite; afterwards, what it expects
    /// from the move it made.
    private var verdict: String? {
        if model.isThinking, let analysis = model.currentAnalysis,
           let column = analysis.bestColumn, let score = analysis.bestScore {
            return "Leaning toward column \(column + 1) (\(ConnectFourFormat.label(for: score)))."
        }
        guard let decision = model.lastDecision, let score = decision.score else { return nil }
        let isDemo = model.human == nil
        let mover = isDemo ? model.color(of: decision.mover).name : "Claude"
        let opponent = isDemo ? model.color(of: decision.mover.opponent).name : "you"
        return ConnectFourFormat.verdict(score: score, mover: mover, opponent: opponent)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// Whose turn it is, at the top left of the stage.
struct ConnectFourStatusHUD: View {
    let model: ConnectFourModel

    var body: some View {
        let status = self.status
        HStack(spacing: 8) {
            StatPill(status.label, status.value)
            StatPill("Discs", "\(model.game.moves.count)")
        }
    }

    private var status: (label: String, value: String) {
        let game = model.game
        if let outcome = game.outcome {
            guard let winner = outcome.winner else { return ("Result", "Draw") }
            guard let human = model.human else { return ("Result", "\(model.color(of: winner).name) wins") }
            return ("Result", winner == human ? "You win" : "Claude wins")
        }
        if model.isHumanTurn {
            return ("Turn", "You")
        }
        let name = model.human == nil ? model.color(of: game.playerToMove).name : "Claude"
        return (name, model.isThinking ? "Thinking…" : "To move")
    }
}

/// Live search statistics, at the top right of the stage.
struct ConnectFourSearchHUD: View {
    let model: ConnectFourModel

    var body: some View {
        if model.isSearching || model.currentAnalysis != nil {
            HStack(spacing: 8) {
                if model.showsAnalysis, let perspective {
                    StatPill("Scores for", perspective)
                }
                StatPill("Depth", depth)
                StatPill("Nodes", ConnectFourFormat.count(model.liveNodes))
            }
        }
    }

    private var depth: String {
        if model.isSearching {
            return "\(model.searchingDepth)"
        }
        guard let analysis = model.currentAnalysis else { return "—" }
        return analysis.isSolved ? "Solved" : "\(analysis.depth)"
    }

    /// Whose options the chips score: the player to move.
    private var perspective: String? {
        guard !model.game.isOver else { return nil }
        let mover = model.game.playerToMove
        guard let human = model.human else { return model.color(of: mover).name }
        return mover == human ? "You" : "Claude"
    }
}
