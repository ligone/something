import SwiftUI
import SortKit

struct SortingExhibit: View {
    var body: some View {
        ExhibitLayout(.sorting) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.sorting.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
