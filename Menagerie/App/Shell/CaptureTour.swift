import AppKit

/// Process-wide facts about how the app was launched.
enum AppEnvironment {
    /// True while CI drives the app through its screenshot tour. Exhibits use
    /// it to start animating on their own (and to stay silent), so the
    /// screenshots show them in action.
    static let isCaptureTour = CommandLine.arguments.contains("--capture")
}

/// `Menagerie --capture <directory> [--dwell <seconds>] [--only a,b,c]`
///
/// Shows each exhibit in turn, saves a PNG of the window for each one, then
/// quits. CI runs it as an end-to-end smoke test and publishes the images.
@MainActor
final class CaptureTour {
    private let directory: URL
    private let dwell: Double
    private let exhibits: [Exhibit]

    init?(arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "--capture"), flag + 1 < arguments.count else {
            return nil
        }
        directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)

        if let index = arguments.firstIndex(of: "--dwell"), index + 1 < arguments.count,
           let seconds = Double(arguments[index + 1]) {
            dwell = seconds
        } else {
            dwell = 4
        }

        if let index = arguments.firstIndex(of: "--only"), index + 1 < arguments.count {
            exhibits = arguments[index + 1]
                .split(separator: ",")
                .compactMap { Exhibit(rawValue: String($0)) }
        } else {
            exhibits = Exhibit.allCases
        }
    }

    func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            for (index, exhibit) in exhibits.enumerated() {
                Navigation.shared.show(exhibit)
                log("showing \(exhibit.rawValue)")
                try? await Task.sleep(for: .seconds(dwell))
                snapshot(named: String(format: "%02d-%@", index, exhibit.rawValue))
            }
            log("tour complete")
            NSApp.terminate(nil)
        }
    }

    private func snapshot(named name: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) else {
            log("no window to capture")
            return
        }

        // 1. Draw the view hierarchy into a bitmap. This needs no special
        //    permission, but Metal layers and vibrancy come out blank.
        if let view = window.contentView?.superview ?? window.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                write(png, to: "\(name).png")
            }
        }

        // 2. Ask the window server for the composited pixels, Metal included.
        //    This only works when the process is allowed to record the screen.
        let screencapture = Process()
        screencapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screencapture.arguments = [
            "-x", "-o", "-l\(window.windowNumber)",
            directory.appendingPathComponent("\(name)-screen.png").path,
        ]
        do {
            try screencapture.run()
            screencapture.waitUntilExit()
        } catch {
            log("screencapture failed: \(error.localizedDescription)")
        }
    }

    private func write(_ data: Data, to fileName: String) {
        do {
            try data.write(to: directory.appendingPathComponent(fileName))
            log("saved \(fileName)")
        } catch {
            log("could not save \(fileName): \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        print("[capture] \(message)")
        fflush(stdout)
    }
}
