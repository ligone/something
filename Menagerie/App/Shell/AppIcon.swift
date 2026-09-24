import AppKit
import CoreGraphics

/// The app icon, drawn in code: a phyllotaxis spiral (the seed pattern of a
/// sunflower, where each seed turns by the golden angle) glowing inside a
/// dark squircle. The build script exports it into the bundle's `.icns`, and
/// `swift run` shows it in the Dock.
enum AppIcon {
    static func image(pixelSize: Int) -> NSImage {
        guard let cgImage = cgImage(pixelSize: pixelSize) else { return NSImage() }
        return NSImage(cgImage: cgImage, size: NSSize(width: pixelSize, height: pixelSize))
    }

    static func cgImage(pixelSize: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let scale = CGFloat(pixelSize) / 1024
        context.scaleBy(x: scale, y: scale)
        drawArtwork(in: context)
        return context.makeImage()
    }

    /// Writes a macOS `.iconset` folder, ready for `iconutil -c icns`.
    static func exportIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for multiplier in [1, 2] {
                let suffix = multiplier == 2 ? "@2x" : ""
                let url = folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                guard let image = cgImage(pixelSize: points * multiplier) else { continue }
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: url)
            }
        }
    }

    /// Draws the 1024 × 1024 master artwork.
    private static func drawArtwork(in context: CGContext) {
        // Apple's macOS icon grid: an 824-point body centered on the canvas.
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
        let center = CGPoint(x: 512, y: 512)

        // Drop shadow under the body.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgba(0, 0, 0, 0.5))
        context.addPath(squircle)
        context.setFillColor(rgba(0.06, 0.05, 0.12))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(squircle)
        context.clip()

        // Night-sky gradient with a violet bloom in the middle.
        let sky = CGGradient(
            colorsSpace: nil,
            colors: [rgba(0.13, 0.09, 0.27), rgba(0.03, 0.03, 0.08)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(sky, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        let bloom = CGGradient(
            colorsSpace: nil,
            colors: [rgba(0.52, 0.36, 1.0, 0.42), rgba(0.52, 0.36, 1.0, 0)] as CFArray,
            locations: [0, 1]
        )!
        context.drawRadialGradient(bloom, startCenter: center, startRadius: 0, endCenter: center, endRadius: 430, options: [])

        // The spiral. Seed n sits at angle n·φ and radius c·√n, which packs the
        // seeds evenly; we draw from the rim inwards so the center sits on top.
        let seeds = 400
        let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
        let spacing = 16.4
        for n in stride(from: seeds, through: 1, by: -1) {
            let t = Double(n) / Double(seeds)
            let radius = spacing * Double(n).squareRoot()
            let angle = Double(n) * goldenAngle
            let x = center.x + CGFloat(radius * cos(angle))
            let y = center.y + CGFloat(radius * sin(angle))
            let dot = CGFloat(3.5 + 8.5 * t)
            let color = spectrum(t)
            context.setShadow(offset: .zero, blur: dot * 1.8, color: color.copy(alpha: 0.9))
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
        }
        context.restoreGState()

        // A hairline highlight around the edge.
        context.addPath(squircle)
        context.setStrokeColor(rgba(1, 1, 1, 0.14))
        context.setLineWidth(3)
        context.strokePath()
    }

    /// Gold at the heart of the spiral, through coral and magenta, to violet
    /// and cyan at the rim.
    private static func spectrum(_ t: Double) -> CGColor {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (1.00, 0.93, 0.62)),
            (0.25, (1.00, 0.62, 0.30)),
            (0.50, (0.98, 0.33, 0.58)),
            (0.75, (0.62, 0.38, 1.00)),
            (1.00, (0.30, 0.78, 1.00)),
        ]
        let clamped = min(max(t, 0), 1)
        for i in 1..<stops.count where clamped <= stops[i].0 {
            let (t0, c0) = stops[i - 1]
            let (t1, c1) = stops[i]
            let f = (clamped - t0) / (t1 - t0)
            return rgba(c0.0 + (c1.0 - c0.0) * f, c0.1 + (c1.1 - c0.1) * f, c0.2 + (c1.2 - c0.2) * f)
        }
        let last = stops[stops.count - 1].1
        return rgba(last.0, last.1, last.2)
    }

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// Command-line utilities that run instead of the app.
enum CommandLineTools {
    /// Returns `true` when a tool handled the invocation and the process
    /// should exit without launching the UI.
    static func run(_ arguments: [String]) -> Bool {
        if let flag = arguments.firstIndex(of: "--export-iconset"), flag + 1 < arguments.count {
            let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
            do {
                try AppIcon.exportIconset(to: folder)
                print("Wrote \(folder.path)")
            } catch {
                FileHandle.standardError.write(Data("Could not export icon: \(error)\n".utf8))
                exit(1)
            }
            return true
        }
        return false
    }
}
