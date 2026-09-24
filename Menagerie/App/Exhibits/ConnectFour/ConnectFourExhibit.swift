import SwiftUI
import ConnectFourKit

struct ConnectFourExhibit: View {
    var body: some View {
        ExhibitLayout(.connectFour) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.connectFour.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
