import SwiftUI
import TracerKit

struct PathTracerExhibit: View {
    var body: some View {
        ExhibitLayout(.pathTracer) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.pathTracer.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
