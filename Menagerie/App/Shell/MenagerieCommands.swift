import AppKit
import SwiftUI

struct MenagerieCommands: Commands {
    let navigation: Navigation

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Menagerie") {
                AboutPanel.show()
            }
        }

        CommandMenu("Exhibits") {
            ForEach(Exhibit.allCases) { exhibit in
                Button(exhibit.title) {
                    navigation.show(exhibit)
                }
                .keyboardShortcut(exhibit.shortcutKey, modifiers: .command)
            }

            Divider()

            Button("Next Exhibit") {
                navigation.showNext()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Button("Previous Exhibit") {
                navigation.showPrevious()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        }
    }
}

enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(
            string: "A cabinet of computational curiosities.\n\nDesigned and written by Claude, in Swift, with no third-party dependencies.",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Menagerie",
            .applicationIcon: AppIcon.image(pixelSize: 256),
            .credits: credits,
        ])
        NSApp.activate()
    }
}
