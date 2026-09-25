# CLAUDE.md

## What's here

- `Menagerie/` is the active project: a native macOS app (SwiftUI, macOS 14+) with nine interactive exhibits. `Menagerie/README.md` describes each exhibit.
- The `*.html`, `style.css` and images at the root are an unrelated static website from 2017. Leave them alone unless asked.

## Commands

Run these from `Menagerie/`.

- `swift test`: every engine test suite (about 440 tests; they also pass on Linux). Filter with `swift test --filter TracerKitTests`.
- `Scripts/build-app.sh [--universal]`: release build to `build/Menagerie.app`, with the icon drawn in code and an ad-hoc signature.
- `Scripts/install.sh`: builds, installs into `~/Applications` and puts a shortcut on the Desktop.
- `Scripts/setup-mac.sh`: the one-command setup people run from GitHub. It clones or updates the repo, runs `install.sh` and opens Claude Code (`MENAGERIE_CLAUDE=continue|fresh|remote|none`).
- `swift run -c release Menagerie`: run from source without a bundle.
- `build/Menagerie.app/Contents/MacOS/Menagerie --verify-shaders`: compiles the runtime Metal shaders and exits.
- `build/Menagerie.app/Contents/MacOS/Menagerie --capture <dir> [--dwell 5] [--only fractals,calculus]`: shows each exhibit in turn and saves `NN-<exhibit>-screen.png`, then quits. That window-server capture needs the terminal to have Screen Recording permission. It also saves `NN-<exhibit>.png`, a view snapshot in which Metal content is blank.

## Layout

- `Engines/<Kit>/` holds every algorithm, one module per exhibit: FractalKit, TracerKit, LifeKit, MazeKit, CalculusKit, ConnectFourKit, ProseKit, SortKit and SynthKit. Engines use only the stdlib, Foundation and Dispatch, so they must keep building on Linux.
- `Tests/<Kit>Tests/` holds the XCTest suites.
- `App/` is the macOS app target. `Package.swift` declares it only on macOS.
  - `Shell/` has the entry point (`MenagerieApp.swift`, which handles the CLI flags), the `Exhibit` registry (titles, summaries, tags, notes), navigation, the menus (⌘0 to ⌘9), `CaptureTour` and `AppIcon`.
  - `DesignSystem/` has `ExhibitLayout` (a dark stage plus a control panel), `ControlSection`, `ParameterSlider`, `StatRow`, `StatPill` with `.stageHUD`, `.stageHint`, `.onScrollWheel`, `PixelImage` and `FrameRateMeter`.
  - `Exhibits/<Name>/` has `<Name>Exhibit.swift` (the entry view), `<Name>Notes.swift` (the "How it works" copy) and the exhibit's models and views.
- To add an exhibit:
  - add a case to `Exhibit` and to `ExhibitDetail` in `Shell/ContentView.swift`;
  - create its folder;
  - add its engine to `engines` in `Package.swift`.

## Conventions

- **Language and APIs.** Tools version 5.9 means Swift 5 language mode. The deployment target is macOS 14, so guard anything newer with `if #available`. Don't use APIs that exist only in the macOS 26 SDK: CI also builds with Xcode 16.4.
- **Naming.** Engine public names must be distinctive (`MazeGrid`, not `Grid`; never `Expression`, which clashes with Foundation). No public extensions on stdlib or Foundation types, because they collide across modules.
- **State and lifecycle.**
  - UI state lives in `@Observable` models on the main actor, held in `@State`.
  - Per-frame simulations live in non-observed classes driven by `TimelineView` and `Canvas`.
  - Exhibit views are torn down when you navigate away, so stop timers, tasks, audio and key monitors in `.onDisappear`.
- **Audio.** Never touch `AVAudioEngine.inputNode`, which triggers the microphone prompt. Render callbacks must not allocate or block.
- **Type checking.** Xcode's type checker can time out on long expressions that mix literals. Split them up with explicit types.
- **Debug builds.** Heavy engines are listed in `optimizedInDebug` in `Package.swift` and compiled with `-O` even in debug builds.

## CI

`.github/workflows/menagerie.yml` runs:
- the engine tests on Linux;
- on macOS with the default and the newest Xcode: the tests, a universal build, `install.sh`, the shader check and the capture tour.

It uploads the app and the screenshots as artifacts.

## Status

This was built in a Claude Code on the web session on branch `claude/hopeful-babbage-djjew8`, then tried by hand on a Mac (macOS 26, Apple silicon, a 4K display). All nine exhibits work at large window sizes, with mouse clicks, drags and the scroll wheel. That pass turned up three bugs, now fixed: a Particle Life crash when the species count drops, the Fractal Explorer's half-resolution draft smearing while zooming, and Language Lab's cards spreading into one thin row on very wide windows.

Still untested by hand:
- what the two audio exhibits sound like (Sound of Sorting now starts with sound on; it used to start muted);
- trackpad gestures (two-finger pan, pinch zoom) and keyboard controls inside exhibits;
- Light Mode, and windows smaller than CI's 1100×752.
