import AppKit
import SwiftUI

/// A mouse-wheel, trackpad-scroll or trackpad-pinch event over a view.
struct ScrollWheelEvent {
    /// Scroll distance in points. Mouse-wheel "lines" are converted to points.
    /// `dy > 0` when a mouse wheel rolls up (away from you); trackpads follow
    /// the user's natural-scrolling preference.
    var delta: CGVector
    /// Pinch amount for trackpad magnify gestures (`0.1` ≈ 10% bigger);
    /// zero for scroll events.
    var magnification: CGFloat
    /// Where the pointer is, in the view's own coordinates (origin top-left).
    var location: CGPoint
    /// Keys held during the event.
    var modifiers: NSEvent.ModifierFlags

    /// A zoom factor that feels natural for both wheels and pinches:
    /// > 1 zooms in, < 1 zooms out.
    var zoomFactor: CGFloat {
        if magnification != 0 { return 1 + magnification }
        return exp(delta.dy * 0.0045)
    }
}

extension View {
    /// Calls `action` for scroll-wheel and pinch events over this view, and
    /// consumes them. SwiftUI has no scroll-wheel gesture on macOS, so this
    /// installs a local event monitor for the view's lifetime.
    func onScrollWheel(_ action: @escaping (ScrollWheelEvent) -> Void) -> some View {
        background(ScrollWheelReader(action: action))
    }
}

private struct ScrollWheelReader: NSViewRepresentable {
    let action: (ScrollWheelEvent) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: ReaderView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class ReaderView: NSView {
        var action: ((ScrollWheelEvent) -> Void)?
        private var monitor: Any?

        // Transparent to clicks; it only watches the event stream.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self, let window = self.window, event.window === window, !self.isHiddenOrHasHiddenAncestor else {
                    return event
                }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local) else { return event }
                let location = CGPoint(x: local.x, y: self.isFlipped ? local.y : self.bounds.height - local.y)

                var delta = CGVector.zero
                var magnification: CGFloat = 0
                if event.type == .magnify {
                    magnification = event.magnification
                } else {
                    let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                    delta = CGVector(dx: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale)
                }
                self.action?(ScrollWheelEvent(
                    delta: delta,
                    magnification: magnification,
                    location: location,
                    modifiers: event.modifierFlags
                ))
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
