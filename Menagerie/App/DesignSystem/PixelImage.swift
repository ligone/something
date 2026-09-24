import CoreGraphics
import Foundation
import QuartzCore

/// Turns raw pixel buffers from the engines into `CGImage`s for display.
enum PixelImage {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Wraps 8-bit RGBA bytes (R, G, B, A in memory order, top row first).
    /// Alpha is treated as premultiplied; pass 255 for opaque pixels.
    static func make(width: Int, height: Int, rgba bytes: [UInt8]) -> CGImage? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        return make(width: width, height: height, data: Data(bytes))
    }

    /// Wraps packed pixels whose bytes are R, G, B, A in memory order, which
    /// on every Mac (little-endian) is the `UInt32` value `0xAABBGGRR`.
    static func make(width: Int, height: Int, packed pixels: [UInt32]) -> CGImage? {
        guard width > 0, height > 0, pixels.count >= width * height else { return nil }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return make(width: width, height: height, data: data)
    }

    private static func make(width: Int, height: Int, data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

/// A smoothed frames-per-second meter. Call `tick()` once per frame.
struct FrameRateMeter {
    private var lastTime: CFTimeInterval?
    private(set) var framesPerSecond: Double = 0

    mutating func tick(now: CFTimeInterval = CACurrentMediaTime()) {
        defer { lastTime = now }
        guard let lastTime else { return }
        let dt = now - lastTime
        guard dt > 0, dt < 1 else { return }
        let instant = 1 / dt
        framesPerSecond = framesPerSecond == 0 ? instant : framesPerSecond * 0.92 + instant * 0.08
    }
}
