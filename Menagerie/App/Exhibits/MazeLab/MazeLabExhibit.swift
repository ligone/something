import SwiftUI
import MazeKit

struct MazeLabExhibit: View {
    var body: some View {
        ExhibitLayout(.mazeLab) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.mazeLab.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
