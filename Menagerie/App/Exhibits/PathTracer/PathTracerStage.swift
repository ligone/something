import AppKit
import SwiftUI
import TracerKit

/// The dark stage: the progressive render scaled to fill, with orbit, dolly,
/// click-to-focus and double-click-to-reset interactions.
struct PathTracerStage: View {
    let model: PathTracerModel

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if let image = model.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                if let mark = model.focusMark {
                    PathTracerFocusReticle(mark: mark)
                        .id(mark.id)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Path-traced render of the \(model.preset.title) scene")
            .accessibilityValue("\(model.stats.samples) samples per pixel")
            .accessibilityAddTraits(.isImage)
            .gesture(orbitGesture)
            .onScrollWheel { event in
                model.dolly(zoomFactor: Double(event.zoomFactor))
            }
            .animation(.easeOut(duration: 0.35), value: model.focusMark)
            .onAppear { model.stageResized(to: size) }
            .onChange(of: size) { _, newSize in
                model.stageResized(to: newSize)
            }
        }
    }

    /// A single drag gesture handles everything the mouse does. Movement
    /// orbits, and a press without movement is a click. The click count comes
    /// from the AppKit event that ended it, so a single click focuses
    /// immediately instead of waiting to rule out a double-click.
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.dragChanged(start: value.startLocation, translation: value.translation)
            }
            .onEnded { value in
                let clicks = NSApp.currentEvent?.clickCount ?? 1
                model.dragEnded(at: value.location, clickCount: clicks)
            }
    }
}

/// An autofocus-style reticle that locks on with a spring, then fades away.
struct PathTracerFocusReticle: View {
    let mark: PathTracerFocusMark
    @State private var locked = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: 9)
                    .offset(y: -28)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Circle()
                .fill(Exhibit.pathTracer.tint)
                .frame(width: 6, height: 6)
        }
        .frame(width: 48, height: 48)
        .scaleEffect(locked ? 1 : 1.9)
        .rotationEffect(.degrees(locked ? 0 : -45))
        .overlay(alignment: .top) {
            Text(mark.caption)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .offset(y: 60)
                .opacity(locked ? 1 : 0)
        }
        .opacity(locked ? 1 : 0)
        .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 1)
        .position(mark.location)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) {
                locked = true
            }
        }
    }
}

/// The live statistics shown over the render.
struct PathTracerHUD: View {
    let model: PathTracerModel

    var body: some View {
        let stats = model.stats
        HStack(spacing: 6) {
            StatPill("Samples", stats.samples.formatted())
            StatPill("Mrays/s", Self.megarays(stats.raysPerSecond))
            StatPill("Time", Self.clock(stats.elapsed))
            StatPill("Size", "\(stats.width)×\(stats.height)")
            if stats.state == .converged {
                StatPill("Status", "Converged")
            } else if model.isPaused {
                StatPill("Status", "Paused")
            }
        }
    }

    static func megarays(_ raysPerSecond: Double) -> String {
        let value = raysPerSecond / 1_000_000
        return String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
