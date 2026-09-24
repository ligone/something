import SwiftUI

struct FractalExhibit: View {
    var body: some View {
        ExhibitLayout(.fractals) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.fractals.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
