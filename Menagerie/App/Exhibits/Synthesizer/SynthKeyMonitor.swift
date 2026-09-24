import AppKit

/// What a key of the computer keyboard does in the synthesizer.
enum SynthKeyAction: Equatable {
    /// Plays the note this many semitones above the keyboard's base C.
    case note(Int)
    case octaveDown
    case octaveUp
}

/// The computer keyboard laid out like a piano: the home row (A S D F G H J K L) plays white keys
/// from C and the row above (W E T Y U O P) the black keys; Z and X shift the octave.
///
/// Matching uses physical key codes (the ANSI positions) rather than characters, so the piano
/// shape stays intact on AZERTY, QWERTZ and Dvorak layouts.
enum SynthKeyMap {
    static func action(for keyCode: UInt16) -> SynthKeyAction? {
        switch keyCode {
        case 0x00: return .note(0) // A → C
        case 0x0D: return .note(1) // W → C♯
        case 0x01: return .note(2) // S → D
        case 0x0E: return .note(3) // E → D♯
        case 0x02: return .note(4) // D → E
        case 0x03: return .note(5) // F → F
        case 0x11: return .note(6) // T → F♯
        case 0x05: return .note(7) // G → G
        case 0x10: return .note(8) // Y → G♯
        case 0x04: return .note(9) // H → A
        case 0x20: return .note(10) // U → A♯
        case 0x26: return .note(11) // J → B
        case 0x28: return .note(12) // K → C
        case 0x1F: return .note(13) // O → C♯
        case 0x25: return .note(14) // L → D
        case 0x23: return .note(15) // P → D♯
        case 0x06: return .octaveDown // Z
        case 0x07: return .octaveUp // X
        default: return nil
        }
    }

    /// Letters printed on the on-screen keys, by semitone above the base C.
    static let labels = ["A", "W", "S", "E", "D", "F", "T", "G", "Y", "H", "U", "J", "K", "O", "L", "P"]
}

/// An app-local keyboard monitor that exists only while the exhibit is on screen.
@MainActor
final class SynthKeyMonitor {
    private var monitor: Any?

    /// Starts monitoring key-down and key-up events.
    ///
    /// - Parameter handler: Called on the main thread; return `true` to consume the event.
    func install(_ handler: @escaping @MainActor @Sendable (NSEvent) -> Bool) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            // Local monitors run on the main thread.
            let consumed = MainActor.assumeIsolated { handler(event) }
            return consumed ? nil : event
        }
    }

    /// Stops monitoring. Safe to call when not installed.
    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
