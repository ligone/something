// swift-tools-version:5.9
import PackageDescription

// Menagerie is split in two layers:
//
//  • Engines/ — portable Swift libraries (no Apple-only frameworks), one per
//    exhibit. They hold every algorithm in the app and build and test on any
//    platform Swift supports, Linux CI included.
//  • App/ — the macOS app. It composes the engines with SwiftUI, AppKit,
//    Metal, AVFoundation and NaturalLanguage, so it only exists on macOS.

let engines = [
    "CalculusKit",
    "ConnectFourKit",
    "LifeKit",
    "MazeKit",
    "ProseKit",
    "SortKit",
    "SynthKit",
    "TracerKit",
]

// Engines that crunch numbers every frame stay optimized in debug builds too,
// so pressing Run in Xcode still gives smooth simulations and real-time audio.
let optimizedInDebug: Set<String> = ["ConnectFourKit", "LifeKit", "SynthKit", "TracerKit"]

var targets: [Target] = []
for engine in engines {
    targets.append(.target(
        name: engine,
        path: "Engines/\(engine)",
        swiftSettings: optimizedInDebug.contains(engine)
            ? [.unsafeFlags(["-O"], .when(configuration: .debug))]
            : []
    ))
    targets.append(.testTarget(
        name: "\(engine)Tests",
        dependencies: [.target(name: engine)],
        path: "Tests/\(engine)Tests"
    ))
}

var products: [Product] = []

#if os(macOS)
targets.append(.executableTarget(
    name: "Menagerie",
    dependencies: engines.map { .target(name: $0) },
    path: "App"
))
products.append(.executable(name: "Menagerie", targets: ["Menagerie"]))
#endif

let package = Package(
    name: "Menagerie",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
