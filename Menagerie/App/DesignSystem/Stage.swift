import SwiftUI

/// The dark backdrop behind every exhibit's stage.
struct StageBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.085), Color(white: 0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.white.opacity(0.045), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 800
            )
        }
        .ignoresSafeArea()
    }
}

/// A translucent read-out that floats over a stage: `FPS 60`, `SAMPLES 128`.
struct StatPill: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .fixedSize()
    }
}

/// A one-line hint about how to interact with a stage.
struct StageHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .fixedSize()
    }
}

extension View {
    /// Floats read-outs (usually `StatPill`s) over a corner of the stage.
    /// Overlays don't take hit tests, so the stage stays interactive underneath.
    func stageHUD<Content: View>(
        _ alignment: Alignment = .topLeading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        overlay(alignment: alignment) {
            HStack(spacing: 8) { content() }
                .padding(14)
                .allowsHitTesting(false)
        }
    }

    /// Adds an interaction hint along the bottom edge of the stage.
    func stageHint(_ text: String) -> some View {
        overlay(alignment: .bottom) {
            StageHint(text: text)
                .padding(.bottom, 14)
                .allowsHitTesting(false)
        }
    }
}
