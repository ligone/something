import SwiftUI
import LifeKit

struct ParticleLifeExhibit: View {
    var body: some View {
        ExhibitLayout(.particleLife) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.particleLife.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
