import AppKit
import SwiftUI

/// The dark stage: an animation timeline drives a `Canvas`, and each frame
/// steps the simulation and redraws every particle.
///
/// Dragging applies a force field at the pointer that pulls particles in and
/// sweeps them along; holding Option pushes them away instead.
struct ParticleLifeStage: View {
    let model: ParticleLifeModel

    var body: some View {
        let simulation = model.simulation
        // While paused, a slow redraw keeps single steps and matrix edits visible.
        let redrawInterval: Double? = model.isPaused ? 1.0 / 15.0 : nil
        TimelineView(.animation(minimumInterval: redrawInterval, paused: !model.isRunning)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true) { context, size in
                simulation.renderFrame(into: &context, size: size, time: time)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    simulation.pointerMoved(to: value.location, repels: NSEvent.modifierFlags.contains(.option))
                }
                .onEnded { _ in
                    simulation.pointerEnded()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Particle life simulation")
        .accessibilityValue("\(model.particleCount) particles of \(model.speciesCount) species, \(model.presetTitle)")
        .accessibilityHint("Drag to attract and stir the particles. Hold Option while dragging to repel them.")
    }
}
