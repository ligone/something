import AppKit
import MetalKit
import SwiftUI

/// Hosts the Metal view and turns mouse, trackpad and keyboard input into
/// model actions.
struct FractalCanvas: NSViewRepresentable {
    let gpu: FractalGPU
    let model: FractalModel

    func makeCoordinator() -> FractalRenderer {
        FractalRenderer(gpu: gpu, model: model)
    }

    func makeNSView(context: Context) -> FractalMTKView {
        let view = FractalMTKView(frame: .zero, device: gpu.device)
        view.model = model
        context.coordinator.configure(view)
        return view
    }

    func updateNSView(_ view: FractalMTKView, context: Context) {
        view.model = model
    }

    static func dismantleNSView(_ view: FractalMTKView, coordinator: FractalRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}

final class FractalMTKView: MTKView {
    weak var model: FractalModel?
    private var lastDragLocation: CGPoint?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        (lastDragLocation == nil ? NSCursor.openHand : NSCursor.closedHand).set()
    }

    /// The event's position in top-left-origin coordinates, matching SwiftUI.
    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        model?.pointerMoved(to: location(of: event))
    }

    override func mouseEntered(with event: NSEvent) {
        model?.pointerMoved(to: location(of: event))
    }

    override func mouseExited(with event: NSEvent) {
        model?.pointerMoved(to: nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = location(of: event)
        if event.clickCount == 2 {
            model?.dive(at: point, outward: event.modifierFlags.contains(.option))
        } else if event.clickCount == 1 {
            model?.click(at: point)
        }
        lastDragLocation = point
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = location(of: event)
        guard let last = lastDragLocation else {
            lastDragLocation = point
            return
        }
        let dx = point.x - last.x
        let dy = point.y - last.y
        lastDragLocation = point
        if event.modifierFlags.contains(.option), model?.kind.isJulia == true {
            model?.morphJulia(dx: dx, dy: dy)
        } else {
            model?.pan(dx: dx, dy: dy)
        }
        model?.pointerMoved(to: point)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
        NSCursor.openHand.set()
    }

    // MARK: Trackpad and wheel

    override func scrollWheel(with event: NSEvent) {
        let point = location(of: event)
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // Trackpad: two fingers pan, like Maps. (⌘ + scroll zooms.)
            model?.pan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        } else {
            // Rolling the wheel away from you zooms in, whatever the
            // natural-scrolling setting.
            var lines = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
            if event.isDirectionInvertedFromDevice { lines = -lines }
            model?.zoom(by: exp(lines * 0.12), at: point)
        }
    }

    override func magnify(with event: NSEvent) {
        model?.zoom(by: 1 + event.magnification, at: location(of: event))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let key: FractalKey?
        switch event.keyCode {
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 53: key = .escape
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "+", "=": key = .zoomIn
            case "-", "_": key = .zoomOut
            case "j": key = .toggleJulia
            case "r": key = .reset
            case "t", " ": key = .toggleTour
            default: key = nil
            }
        }
        if let key, !event.modifierFlags.contains(.command) {
            model?.keyPressed(key)
        } else {
            super.keyDown(with: event)
        }
    }
}
