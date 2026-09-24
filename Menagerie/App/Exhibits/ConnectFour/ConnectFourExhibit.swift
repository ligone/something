import AppKit
import ConnectFourKit
import SwiftUI

/// Connect Four against Claude: a bitboard alpha-beta engine that shows its
/// evaluation of every column as it thinks.
struct ConnectFourExhibit: View {
    @State private var model = ConnectFourModel()
    @State private var keyMonitor: Any?

    var body: some View {
        ExhibitLayout(.connectFour) {
            ConnectFourStage(model: model)
                .stageHUD(.topLeading) {
                    ConnectFourStatusHUD(model: model)
                }
                .stageHUD(.topTrailing) {
                    ConnectFourSearchHUD(model: model)
                }
                .stageHint(hint)
        } controls: {
            ConnectFourControls(model: model)
        }
        .onAppear {
            model.start()
            installKeyMonitor()
        }
        .onDisappear {
            model.stop()
            removeKeyMonitor()
        }
    }

    private var hint: String {
        if model.isDemo {
            return "Claude is playing both sides. Turn off Watch Claude play itself to take over."
        }
        return "Click a column or press 1–7 to drop a disc. H shows a hint, U takes back a move."
    }

    // MARK: - Keyboard

    /// Keys 1–7, H and U work whenever the exhibit is on screen, without
    /// first clicking the board to focus it.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let model = self.model
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                ConnectFourKeyboard.handle(event, model: model)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

/// Turns key presses into moves.
@MainActor
enum ConnectFourKeyboard {
    /// Returns true when the key belongs to the game, so the event stops
    /// here instead of beeping.
    static func handle(_ event: NSEvent, model: ConnectFourModel) -> Bool {
        let shortcuts: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(shortcuts).isEmpty else { return false }
        // Typing in a text field is not a move.
        if event.window?.firstResponder is NSText { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return model.handleKey(key, isRepeat: event.isARepeat)
    }
}
