import SwiftUI

/// The layout every exhibit shares: an immersive stage that is always dark,
/// plus a column on the right with the exhibit's controls and its
/// "How it works" notes. A toolbar button hides the column.
///
///     ExhibitLayout(.pathTracer) {
///         RenderView(...)                      // the stage
///     } controls: {
///         ControlSection("Camera") { ... }     // the panel
///     }
struct ExhibitLayout<Stage: View, Controls: View>: View {
    let exhibit: Exhibit
    private let stage: Stage
    private let controls: Controls

    @AppStorage("controlPanelVisible") private var panelVisible = true

    init(
        _ exhibit: Exhibit,
        @ViewBuilder stage: () -> Stage,
        @ViewBuilder controls: () -> Controls
    ) {
        self.exhibit = exhibit
        self.stage = stage()
        self.controls = controls()
    }

    var body: some View {
        HStack(spacing: 0) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StageBackground())
                .clipped()
                .environment(\.colorScheme, .dark)

            if panelVisible {
                Divider()
                ControlPanel(exhibit: exhibit) { controls }
                    .frame(width: ExhibitMetrics.panelWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle(exhibit.title)
        .navigationSubtitle(exhibit.subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { panelVisible.toggle() }
                } label: {
                    Label(panelVisible ? "Hide Controls" : "Show Controls", systemImage: "sidebar.trailing")
                }
                .help(panelVisible ? "Hide the control panel" : "Show the control panel")
            }
        }
    }
}

enum ExhibitMetrics {
    static let panelWidth: CGFloat = 300
    static let panelPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 22
}

/// The scrolling right-hand column: controls first, then the notes.
struct ControlPanel<Content: View>: View {
    let exhibit: Exhibit
    private let content: Content

    init(exhibit: Exhibit, @ViewBuilder content: () -> Content) {
        self.exhibit = exhibit
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExhibitMetrics.sectionSpacing) {
                content
                Divider()
                NotesView(notes: exhibit.notes, tint: exhibit.tint)
            }
            .padding(ExhibitMetrics.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Renders an exhibit's `ExhibitNotes`.
struct NotesView: View {
    let notes: ExhibitNotes
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("How it works", systemImage: "lightbulb.max")
                .font(.headline)
                .foregroundStyle(tint)

            Text(Self.markdown(notes.lede))
                .font(.callout)

            ForEach(notes.sections, id: \.self) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                    Text(Self.markdown(section.body))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    static func markdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
