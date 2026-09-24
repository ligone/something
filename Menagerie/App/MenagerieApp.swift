import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        // A couple of command-line utilities (used by Scripts/build-app.sh and
        // CI) run and exit without ever showing a window.
        if CommandLineTools.run(CommandLine.arguments) {
            return
        }
        MenagerieApp.main()
    }
}

struct MenagerieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Menagerie", id: "main") {
            ContentView()
                .environment(Navigation.shared)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            MenagerieCommands(navigation: Navigation.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var capture: CaptureTour?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` launches a bare executable with no bundle. Promote it to
        // a regular app so it gets a Dock icon, a menu bar and keyboard focus.
        if Bundle.main.bundleURL.pathExtension != "app" {
            NSApp.setActivationPolicy(.regular)
            NSApp.applicationIconImage = AppIcon.image(pixelSize: 512)
        }
        NSApp.activate()

        if let tour = CaptureTour(arguments: CommandLine.arguments) {
            capture = tour
            tour.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
