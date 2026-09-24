import SwiftUI
import ProseKit

struct LanguageLabExhibit: View {
    var body: some View {
        ExhibitLayout(.languageLab) {
            ContentUnavailableView("Under construction", systemImage: Exhibit.languageLab.symbol)
        } controls: {
            ControlSection("Controls") {
                Text("Coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
