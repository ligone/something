import ConnectFourKit
import Foundation
import Observation

/// A disc as the board draws it.
struct ConnectFourDisc: Equatable {
    var cell: C4Cell
    var color: ConnectFourDiscColor
    /// When the disc was released above the board, or, for a disc taken back
    /// by Undo, when it began to fade.
    var start: Date
}

/// What Claude concluded when it last chose a move.
struct ConnectFourDecision {
    let analysis: C4Analysis
    let column: Int
    let mover: C4Player

    var score: C4Score? {
        analysis.scores[column]
    }
}

/// Your results since the exhibit opened.
struct ConnectFourRecord: Equatable {
    var wins = 0
    var losses = 0
    var draws = 0

    var total: Int {
        wins + losses + draws
    }
}

/// The state of the Connect Four exhibit: the game, whose turn it is, and the
/// engine searches that run in the background.
///
/// Searches run on a detached task so the interface stays smooth, and stream
/// their progress back to the main actor. Every search carries the game's
/// `generation` number, so results that arrive after a new game, an undo or a
/// move are ignored.
@MainActor
@Observable
final class ConnectFourModel {
    // MARK: - Settings

    /// How hard Claude plays. Takes effect from Claude's next move.
    var difficulty: C4Difficulty = .strong
    /// Whether the evaluation chips and threat markers are shown.
    var showsAnalysis = true
    /// Seconds between moves while Claude plays itself.
    var demoPause = 0.8

    /// Whether you drop the first disc. A game in which you have not moved
    /// yet restarts at once; otherwise the change applies to the next game.
    var youMoveFirst = true {
        didSet {
            guard youMoveFirst != oldValue, hasStarted, !isDemo, !hasHumanMoves else { return }
            newGame()
        }
    }

    /// Whether Claude plays both sides. Switching starts a new game.
    var isDemo = false {
        didSet {
            guard isDemo != oldValue, hasStarted else { return }
            newGame()
        }
    }

    // MARK: - Game

    private(set) var game = C4Game()
    /// The player you control, or nil while Claude plays itself.
    private(set) var human: C4Player? = .first
    /// Every disc on the board, in move order.
    private(set) var discs: [ConnectFourDisc] = []
    /// Discs taken back by Undo that are still fading out.
    private(set) var fading: [ConnectFourDisc] = []
    /// Whether a disc is falling or fading, so the board redraws every frame.
    private(set) var isMoving = false
    /// When the winning line starts to glow: as the last disc lands.
    private(set) var winRevealDate: Date?
    /// Whether the result banner is up. It waits for the winning line.
    private(set) var showsResult = false
    private(set) var record = ConnectFourRecord()

    // MARK: - Pointer and hint

    /// The column under the pointer.
    private(set) var hoverColumn: Int?
    /// The column the hint recommends.
    private(set) var hintColumn: Int?

    // MARK: - Engine

    /// The latest analysis of the current position, for the chips.
    private(set) var analysis: C4Analysis?
    /// Whether Claude is choosing its move.
    private(set) var isThinking = false
    /// Whether any search is running, including the analysis on your turn.
    private(set) var isSearching = false
    private(set) var searchingDepth = 0
    private(set) var liveNodes = 0
    private(set) var liveElapsed = 0.0
    /// Claude's last decision, for the statistics and the verdict.
    private(set) var lastDecision: ConnectFourDecision?

    private let engine = C4Engine()
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var motionTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var restingDate = Date.distantPast
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var resultRecorded = false
    @ObservationIgnored private var wantsHint = false

    /// Claude never answers faster than this, so its move reads as a reply.
    private static let minimumThinkTime = 0.55

    /// A natural opening for the screenshot tour, so the capture shows a
    /// game in full swing rather than an empty board.
    static let showcaseOpening = [3, 3, 3, 4, 2, 2, 4, 1, 5, 3]
    /// Quick moves for the screenshot tour.
    private static let showcaseLimits = C4SearchLimits(maxDepth: 42, timeBudget: 0.35)

    // MARK: - Lifecycle

    /// Starts the first game, or picks up where things stopped when the
    /// exhibit reappears.
    func start() {
        guard !hasStarted else {
            if restingDate > Date() || !fading.isEmpty {
                markMoving(until: max(restingDate, Date()))
            }
            advance()
            return
        }
        if AppEnvironment.isCaptureTour {
            isDemo = true
            demoPause = 0.3
        }
        hasStarted = true
        startGame(opening: AppEnvironment.isCaptureTour ? Self.showcaseOpening : [])
    }

    /// Stops every search and timer. Called when the exhibit disappears.
    func stop() {
        cancelWork()
        motionTask?.cancel()
        motionTask = nil
        isMoving = false
    }

    // MARK: - Commands

    /// Starts a fresh game with the current settings.
    func newGame() {
        startGame(opening: [])
    }

    /// Drops your disc into `column`, if it is your turn and there is room.
    func drop(in column: Int) {
        guard isHumanTurn, game.board.canPlay(column) else { return }
        // Let the previous disc land first, so a double click cannot play twice.
        guard Date() >= restingDate.addingTimeInterval(-0.12) else { return }
        play(column)
    }

    /// Whether Undo has one of your moves to take back.
    var canUndo: Bool {
        hasHumanMoves
    }

    /// Takes back your last move, and Claude's reply if it made one.
    func undo() {
        guard let human, hasHumanMoves else { return }
        cancelWork()
        generation += 1
        if resultRecorded {
            unrecordResult()
        }

        let now = Date()
        var removedYours = false
        while !removedYours, let index = game.moves.indices.last {
            let player = game.player(ofMove: index)
            if let disc = discs.popLast() {
                fading.append(ConnectFourDisc(cell: disc.cell, color: disc.color, start: now))
            }
            game.undo()
            removedYours = player == human
        }

        winRevealDate = nil
        showsResult = false
        analysis = nil
        hintColumn = nil
        restingDate = now
        markMoving(until: now.addingTimeInterval(ConnectFourPhysics.vanishDuration))
        advance()
    }

    /// Whether a hint is available: on your turn.
    var canHint: Bool {
        isHumanTurn
    }

    /// Highlights the engine's best move for you. If the analysis of your
    /// position is still shallow, the hint appears when it finishes.
    func showHint() {
        guard isHumanTurn else { return }
        if let analysis, analysis.board == game.board, let best = analysis.bestColumn,
           !isSearching || analysis.depth >= 10 || analysis.isSolved {
            hintColumn = best
        } else {
            wantsHint = true
        }
    }

    /// Tracks the pointer over the columns.
    func hover(_ column: Int, isInside: Bool) {
        if isInside {
            hoverColumn = column
        } else if hoverColumn == column {
            hoverColumn = nil
        }
    }

    /// Handles a key typed while the exhibit is on screen: 1–7 drop a disc,
    /// H asks for a hint and U undoes. Returns whether the key is one of these.
    func handleKey(_ key: String, isRepeat: Bool) -> Bool {
        switch key {
        case "1", "2", "3", "4", "5", "6", "7":
            if !isRepeat, let number = Int(key) {
                drop(in: number - 1)
            }
            return true
        case "h":
            if !isRepeat { showHint() }
            return true
        case "u":
            if !isRepeat { undo() }
            return true
        default:
            return false
        }
    }

    // MARK: - Presentation

    /// The color of `player`'s discs in this game.
    func color(of player: C4Player) -> ConnectFourDiscColor {
        if let human {
            return player == human ? .red : .yellow
        }
        return player == .first ? .red : .yellow
    }

    /// "You" and "Claude", or the colors when Claude plays itself.
    func name(of player: C4Player) -> String {
        guard let human else { return color(of: player).name }
        return player == human ? "You" : "Claude"
    }

    var isHumanTurn: Bool {
        !game.isOver && game.playerToMove == human
    }

    /// Where your disc would hover: the column under the pointer on your turn.
    var previewColumn: Int? {
        guard isHumanTurn, let column = hoverColumn, game.board.canPlay(column) else { return nil }
        return column
    }

    /// Where Claude's translucent disc hovers while it thinks: its current
    /// favorite, which changes as the search deepens.
    var ghostColumn: Int? {
        guard isThinking else { return nil }
        if let analysis, analysis.board == game.board, let best = analysis.bestColumn {
            return best
        }
        return C4Analysis.centerOrder.first(where: game.board.canPlay)
    }

    /// The analysis of the current position, if one is ready.
    var currentAnalysis: C4Analysis? {
        guard let analysis, analysis.board == game.board, !game.isOver else { return nil }
        return analysis
    }

    // MARK: - Turns

    private var hasHumanMoves: Bool {
        guard let human else { return false }
        return game.moves.indices.contains { game.player(ofMove: $0) == human }
    }

    private func startGame(opening: [Int]) {
        cancelWork()
        generation += 1
        game = C4Game()
        discs = []
        fading = []
        analysis = nil
        lastDecision = nil
        hintColumn = nil
        winRevealDate = nil
        showsResult = false
        resultRecorded = false
        human = isDemo ? nil : (youMoveFirst ? .first : .second)

        for column in opening {
            let player = game.playerToMove
            let row = game.board.height(ofColumn: column)
            do {
                try game.play(column)
            } catch {
                break
            }
            discs.append(ConnectFourDisc(cell: C4Cell(column: column, row: row), color: color(of: player), start: .distantPast))
        }
        restingDate = Date()
        advance()
    }

    /// Decides what happens next after the position changes.
    private func advance() {
        cancelWork()
        if game.isOver {
            finishGame()
        } else if isHumanTurn {
            analyzeForHuman()
        } else {
            startClaudeTurn()
        }
    }

    private func play(_ column: Int) {
        let player = game.playerToMove
        let row = game.board.height(ofColumn: column)
        do {
            try game.play(column)
        } catch {
            return
        }

        let now = Date()
        discs.append(ConnectFourDisc(cell: C4Cell(column: column, row: row), color: color(of: player), start: now))
        let landing = now.addingTimeInterval(ConnectFourPhysics.duration(toRow: row))
        restingDate = max(restingDate, landing)
        analysis = nil
        hintColumn = nil
        if game.outcome?.winner != nil {
            winRevealDate = landing
        }
        markMoving(until: landing)
        advance()
    }

    /// Claude searches at once, even while the last disc is still falling,
    /// so the chips come alive immediately. It moves once the search is done,
    /// the disc has landed and the pause has passed.
    private func startClaudeTurn() {
        let token = generation
        let board = game.board
        let mover = board.playerToMove
        let level = difficulty
        let limits = AppEnvironment.isCaptureTour ? Self.showcaseLimits : level.limits
        let pause = isDemo ? demoPause : 0.15
        let earliest = Date().addingTimeInterval(Self.minimumThinkTime)
        isThinking = true

        turnTask = Task { [weak self] in
            guard let self else { return }
            guard let result = await self.search(board, limits: limits, token: token) else { return }
            await Self.sleep(until: max(earliest, self.restingDate.addingTimeInterval(pause)))
            guard self.isCurrent(token) else { return }

            var generator = SystemRandomNumberGenerator()
            guard let column = level.chooseColumn(from: result, using: &generator) else { return }
            self.isThinking = false
            self.lastDecision = ConnectFourDecision(analysis: result, column: column, mover: mover)
            self.play(column)
        }
    }

    /// On your turn the engine analyzes your options, for the chips and the
    /// hint.
    private func analyzeForHuman() {
        let token = generation
        let board = game.board
        turnTask = Task { [weak self] in
            guard let self else { return }
            guard let result = await self.search(board, limits: .analysis, token: token) else { return }
            if self.wantsHint {
                self.wantsHint = false
                self.hintColumn = result.bestColumn
            }
        }
    }

    private func finishGame() {
        isThinking = false
        if !resultRecorded, let human {
            resultRecorded = true
            if let winner = game.outcome?.winner {
                if winner == human { record.wins += 1 } else { record.losses += 1 }
            } else {
                record.draws += 1
            }
        }

        // Raise the banner once the winning line has had a moment to glow.
        let token = generation
        let reveal = (winRevealDate ?? restingDate).addingTimeInterval(0.55)
        timerTask = Task { [weak self] in
            await Self.sleep(until: reveal)
            guard let self, self.isCurrent(token) else { return }
            self.showsResult = true
            guard self.isDemo else { return }
            // Claude plays itself: start another game after a pause.
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard self.isCurrent(token), self.isDemo else { return }
            self.newGame()
        }
    }

    private func unrecordResult() {
        resultRecorded = false
        guard let human else { return }
        if let winner = game.outcome?.winner {
            if winner == human { record.wins -= 1 } else { record.losses -= 1 }
        } else if game.isOver {
            record.draws -= 1
        }
    }

    // MARK: - Searching

    /// Runs the engine on a background thread and streams its progress into
    /// `analysis`. Returns nil if the search was cancelled or overtaken.
    private func search(_ board: C4Board, limits: C4SearchLimits, token: Int) async -> C4Analysis? {
        isSearching = true
        searchingDepth = 1
        liveNodes = 0
        liveElapsed = 0

        let engine = self.engine
        let flag = C4StopFlag()
        let report: @Sendable (C4SearchUpdate) -> Void = { update in
            Task { @MainActor in
                self.receive(update, token: token)
            }
        }
        let result = await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                engine.analyze(board, limits: limits, shouldStop: { flag.isRaised }, onUpdate: report)
            }.value
        } onCancel: {
            flag.raise()
        }

        guard isCurrent(token), result.board == game.board else { return nil }
        isSearching = false
        if result.depth > 0 {
            analysis = result
        }
        searchingDepth = result.depth
        liveNodes = result.nodes
        liveElapsed = result.elapsed
        return result
    }

    private func receive(_ update: C4SearchUpdate, token: Int) {
        guard token == generation, isSearching, update.analysis.board == game.board,
              update.nodes >= liveNodes else { return }
        // Heartbeats repeat the last finished iteration; only a deeper one
        // needs to reach the chips.
        let depth = update.analysis.depth
        if depth > 0, analysis?.board != game.board || depth > (analysis?.depth ?? 0) {
            analysis = update.analysis
        }
        searchingDepth = update.searchingDepth
        liveNodes = update.nodes
        liveElapsed = update.elapsed
    }

    private func isCurrent(_ token: Int) -> Bool {
        !Task.isCancelled && token == generation
    }

    private func cancelWork() {
        turnTask?.cancel()
        turnTask = nil
        timerTask?.cancel()
        timerTask = nil
        isThinking = false
        isSearching = false
        wantsHint = false
    }

    // MARK: - Animation timing

    /// Keeps the board redrawing every frame until `end`.
    private func markMoving(until end: Date) {
        isMoving = true
        motionTask?.cancel()
        motionTask = Task { [weak self] in
            await Self.sleep(until: end.addingTimeInterval(0.05))
            guard let self, !Task.isCancelled else { return }
            self.isMoving = false
            self.fading.removeAll()
        }
    }

    private static func sleep(until date: Date) async {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
