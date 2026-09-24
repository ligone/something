import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Why a PNG couldn't be saved.
enum PathTracerExportError: LocalizedError {
    case cannotCreateFile(URL)
    case cannotWriteImage(URL)

    var errorDescription: String? {
        switch self {
        case let .cannotCreateFile(url):
            return "Couldn't create \(url.lastPathComponent)."
        case let .cannotWriteImage(url):
            return "Couldn't write the image to \(url.lastPathComponent)."
        }
    }
}

/// Saves the current render as a PNG.
@MainActor
enum PathTracerExport {
    /// Shows a save panel and writes `image` wherever the user chooses.
    static func presentSavePanel(for image: CGImage, suggestedName: String) {
        let panel = NSSavePanel()
        panel.title = "Save Render"
        panel.prompt = "Save"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try writePNG(image, to: url)
            } catch {
                _ = NSAlert(error: error).runModal()
            }
        }
    }

    /// Encodes `image` as PNG with ImageIO.
    nonisolated static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PathTracerExportError.cannotCreateFile(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PathTracerExportError.cannotWriteImage(url)
        }
    }
}
