import SwiftUI
import SynthKit

struct SynthesizerExhibit: View {
    var body: some View {
        ExhibitLayout(.synthesizer) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.synthesizer.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
