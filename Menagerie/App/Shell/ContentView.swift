import SwiftUI

struct ContentView: View {
    @Environment(Navigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView {
            Sidebar(selection: $navigation.selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            ExhibitDetail(exhibit: navigation.current)
                // A fresh identity per exhibit: leaving an exhibit tears down its
                // views, which stops its timers, audio and background work.
                .id(navigation.current)
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: Exhibit?

    var body: some View {
        List(selection: $selection) {
            SidebarRow(exhibit: .welcome)
                .tag(Exhibit.welcome)

            ForEach(ExhibitGroup.allCases) { group in
                Section(group.title) {
                    ForEach(group.exhibits) { exhibit in
                        SidebarRow(exhibit: exhibit)
                            .tag(exhibit)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRow: View {
    let exhibit: Exhibit

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(exhibit.title)
                if exhibit != .welcome {
                    Text(exhibit.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: exhibit.symbol)
                .foregroundStyle(exhibit.tint)
        }
        .padding(.vertical, 2)
    }
}

/// Routes an exhibit to its view.
struct ExhibitDetail: View {
    let exhibit: Exhibit

    var body: some View {
        switch exhibit {
        case .welcome: WelcomeView()
        case .fractals: FractalExhibit()
        case .pathTracer: PathTracerExhibit()
        case .particleLife: ParticleLifeExhibit()
        case .mazeLab: MazeLabExhibit()
        case .calculus: CalculusExhibit()
        case .connectFour: ConnectFourExhibit()
        case .languageLab: LanguageLabExhibit()
        case .sorting: SortingExhibit()
        case .synthesizer: SynthesizerExhibit()
        }
    }
}
