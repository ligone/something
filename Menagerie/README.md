# Menagerie

**A cabinet of computational curiosities: a native macOS app, designed and written by Claude.**

Menagerie is a gallery of nine interactive exhibits. Each one is a small, complete program that shows a different kind of work: GPU programming, physically based rendering, simulation, classic algorithms, computer algebra, game-tree search, natural-language processing and real-time audio synthesis. It is written in Swift with SwiftUI and has no third-party dependencies. Everything runs on your Mac, with no network access.

<!-- EXHIBITS -->

## Running it

You need **macOS 14 Sonoma or later**. Building also needs Xcode 15 or later, or its Command Line Tools.

**Build a double-clickable app** (recommended):

```sh
cd Menagerie
Scripts/build-app.sh          # add --universal for an Apple silicon + Intel binary
open build/Menagerie.app
```

The script compiles in release mode, assembles `build/Menagerie.app`, draws the app icon in code, and signs the bundle ad hoc.

**Or run straight from source:**

```sh
cd Menagerie
swift run -c release Menagerie
```

**Or open `Menagerie/Package.swift` in Xcode** and press ⌘R. The heavy engines are compiled with optimizations even in Debug, so the simulations stay smooth.

**Or download a prebuilt app.** Every CI run uploads a universal `Menagerie-app` artifact on the [Actions tab](../../actions/workflows/menagerie.yml). The app is signed ad hoc, not notarized, so macOS will refuse to open the downloaded copy at first. To allow it, either right-click → **Open**, or go to **System Settings → Privacy & Security → Open Anyway**. You can also run `xattr -dr com.apple.quarantine Menagerie.app`.

## Getting around

| Shortcut | Action |
| --- | --- |
| ⌘0 – ⌘9 | Jump to Welcome or to an exhibit |
| ⌥⌘↓ / ⌥⌘↑ | Next / previous exhibit |
| Toolbar ▸ sidebar icon | Show or hide an exhibit's control panel |

Each exhibit's control panel ends with **How it works**: short notes on the algorithms and techniques behind it.

## How it's built

```
Menagerie/
├── Package.swift        # SwiftPM manifest: engines + the macOS app
├── Engines/             # Portable Swift libraries, one per exhibit
├── Tests/               # XCTest suites for every engine (they pass on Linux too)
├── App/
│   ├── Shell/           # App entry point, navigation, menus, icon, CI tour
│   ├── DesignSystem/    # Shared layout, controls, stage overlays
│   └── Exhibits/        # One folder per exhibit: SwiftUI views + platform glue
└── Scripts/build-app.sh # Builds, bundles, draws the icon and signs the app
```

The code is split into two layers:

- **Engines** hold every algorithm: the path tracer, maze generators and solvers, symbolic calculus, the Connect Four search, the particle simulation, the synthesizer's DSP, text analytics and the fractal math. They use only the Swift standard library, Foundation and Dispatch, so they build and test on any platform Swift supports.
- **The app** composes the engines with SwiftUI, AppKit, Metal, AVFoundation, NaturalLanguage and Swift Charts.

[`.github/workflows/menagerie.yml`](../.github/workflows/menagerie.yml) runs the engine tests on Linux and macOS. It then builds a universal app bundle with both the default and the newest Xcode, compiles the runtime Metal shaders, and runs the app through a scripted tour that screenshots every exhibit.

## License

Public domain ([Unlicense](../LICENSE)), like the rest of this repository.
