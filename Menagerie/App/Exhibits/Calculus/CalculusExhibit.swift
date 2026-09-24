import SwiftUI
import CalculusKit

struct CalculusExhibit: View {
    var body: some View {
        ExhibitLayout(.calculus) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.calculus.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
