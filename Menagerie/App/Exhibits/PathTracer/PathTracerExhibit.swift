import SwiftUI

/// A progressive Monte Carlo path tracer that converges live on screen.
///
/// The TracerKit engine renders on every core in a background session. This
/// view shows the result, turns mouse input into camera moves, and exposes
/// the lens, light transport and render settings.
struct PathTracerExhibit: View {
    @State private var model = PathTracerModel()

    var body: some View {
        ExhibitLayout(.pathTracer) {
            PathTracerStage(model: model)
                .stageHUD(.topLeading) {
                    PathTracerHUD(model: model)
                }
                .stageHint("Drag to orbit · Scroll to dolly · Click to focus · Double-click to reset")
        } controls: {
            PathTracerControls(model: model)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
