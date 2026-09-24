import SwiftUI

/// Particle Life: thousands of particles of a few species, each pulled or
/// pushed by its neighbors according to a small attraction matrix. Cells,
/// worms and spinning galaxies emerge from those rules alone.
struct ParticleLifeExhibit: View {
    @State private var model = ParticleLifeModel()

    var body: some View {
        ExhibitLayout(.particleLife) {
            ParticleLifeStage(model: model)
                .stageHUD {
                    HStack(spacing: 8) {
                        StatPill("Particles", model.particleCount.formatted())
                        StatPill("Species", "\(model.speciesCount)")
                        StatPill("FPS", model.framesPerSecondText)
                    }
                }
                .stageHint("Drag to stir and attract · ⌥-drag to repel")
        } controls: {
            ParticleLifeControls(model: model)
        }
        .onAppear {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }
}
