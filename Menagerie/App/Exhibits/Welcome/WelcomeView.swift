import SwiftUI

struct WelcomeView: View {
    @Environment(Navigation.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                WelcomeHero {
                    let exhibits = Exhibit.allCases.filter { $0 != .welcome }
                    if let pick = exhibits.randomElement() { navigation.show(pick) }
                }

                ForEach(ExhibitGroup.allCases) { group in
                    GroupShelf(group: group) { navigation.show($0) }
                }

                Colophon()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Menagerie")
        .navigationSubtitle(Exhibit.welcome.subtitle)
    }
}

// MARK: - Hero

private struct WelcomeHero: View {
    let surpriseMe: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ConstellationView()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                Text("MENAGERIE")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.65))

                Text("A cabinet of computational curiosities")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 0.84, green: 0.78, blue: 1.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)

                Text("Nine interactive exhibits: GPU fractals, a path tracer, artificial life, graph search, computer algebra, a game engine, linguistics and two kinds of sound synthesis. Claude designed and wrote every one in plain Swift. Nothing leaves your Mac and there are no third-party dependencies.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: 700, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button(action: surpriseMe) {
                        Label("Surprise Me", systemImage: "dice.fill")
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color(red: 0.5, green: 0.36, blue: 1.0))

                    Text("Or jump anywhere with ⌘1 – ⌘9")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 6)
            }
            .padding(36)
        }
        .frame(minHeight: 380)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

/// Drifting stars that link up when they pass close to each other, or to the
/// pointer. Every position is a pure function of time, so there's no
/// simulation state to keep.
private struct ConstellationView: View {
    private let stars = Star.field(count: 120)
    @State private var pointer: CGPoint?

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.06, blue: 0.19), Color(red: 0.02, green: 0.02, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): pointer = location
            case .ended: pointer = nil
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let reach: CGFloat = 125
        let points = stars.map { $0.position(at: time, in: size) }

        // Links, grouped into a few opacity bands so each band is one stroke.
        var bands = Array(repeating: Path(), count: 4)
        for i in points.indices {
            for j in (i + 1)..<points.count {
                let dx = points[i].x - points[j].x
                let dy = points[i].y - points[j].y
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance < reach else { continue }
                let band = min(3, Int((distance / reach) * 4))
                bands[band].move(to: points[i])
                bands[band].addLine(to: points[j])
            }
        }
        for (band, path) in bands.enumerated() {
            let opacity = 0.34 * pow(1 - Double(band) / 4, 1.6)
            context.stroke(path, with: .color(Color(red: 0.72, green: 0.7, blue: 1).opacity(opacity)), lineWidth: 0.8)
        }

        // The pointer pulls in nearby stars with brighter threads.
        if let pointer {
            var threads = Path()
            for point in points {
                let dx = point.x - pointer.x
                let dy = point.y - pointer.y
                if dx * dx + dy * dy < 170 * 170 {
                    threads.move(to: pointer)
                    threads.addLine(to: point)
                }
            }
            context.stroke(threads, with: .color(.white.opacity(0.28)), lineWidth: 0.8)
            let halo = CGRect(x: pointer.x - 30, y: pointer.y - 30, width: 60, height: 60)
            context.fill(
                Path(ellipseIn: halo),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.35), .clear]),
                    center: pointer, startRadius: 0, endRadius: 30
                )
            )
        }

        // Stars, twinkling gently.
        for (star, point) in zip(stars, points) {
            let twinkle = 0.75 + 0.25 * sin(time * star.twinkleSpeed + star.phase)
            let radius = star.radius * CGFloat(twinkle)
            let glow = CGRect(x: point.x - radius * 3, y: point.y - radius * 3, width: radius * 6, height: radius * 6)
            context.fill(Path(ellipseIn: glow), with: .color(star.color.opacity(0.16 * twinkle)))
            let core = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: core), with: .color(star.color.opacity(0.95)))
        }
    }
}

private struct Star {
    var origin: CGPoint      // in unit coordinates
    var velocity: CGVector   // unit coordinates per second
    var radius: CGFloat
    var color: Color
    var twinkleSpeed: Double
    var phase: Double

    /// Stars wrap around a region slightly larger than the view, so they
    /// drift off-screen before they reappear on the other side.
    func position(at time: Double, in size: CGSize) -> CGPoint {
        let margin = 0.08
        let span = 1 + 2 * margin
        func wrap(_ value: Double) -> Double {
            let r = value.truncatingRemainder(dividingBy: span)
            return (r < 0 ? r + span : r) - margin
        }
        let x = wrap(Double(origin.x) + Double(velocity.dx) * time)
        let y = wrap(Double(origin.y) + Double(velocity.dy) * time)
        return CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }

    static func field(count: Int) -> [Star] {
        var generator = SeededGenerator(seed: 0x5EED_CAFE)
        let palette = Exhibit.allCases.filter { $0 != .welcome }.map(\.tint) + [.white, .white, .white]
        return (0..<count).map { _ in
            Star(
                origin: CGPoint(x: .random(in: 0...1, using: &generator), y: .random(in: 0...1, using: &generator)),
                velocity: CGVector(
                    dx: .random(in: -0.012...0.012, using: &generator),
                    dy: .random(in: -0.02...0.02, using: &generator)
                ),
                radius: .random(in: 0.9...2.4, using: &generator),
                color: palette.randomElement(using: &generator)!,
                twinkleSpeed: .random(in: 0.6...2.2, using: &generator),
                phase: .random(in: 0...(2 * .pi), using: &generator)
            )
        }
    }
}

/// SplitMix64: a tiny, fast, seedable random number generator.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Shelves of exhibit cards

private struct GroupShelf: View {
    let group: ExhibitGroup
    let open: (Exhibit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(group.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(group.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                ForEach(group.exhibits) { exhibit in
                    ExhibitCard(exhibit: exhibit) { open(exhibit) }
                }
            }
        }
    }
}

private struct ExhibitCard: View {
    let exhibit: Exhibit
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ExhibitGlyph(exhibit: exhibit, size: 46)
                    Spacer()
                    Text("⌘\(String(exhibit.shortcutKey.character))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(exhibit.title)
                        .font(.title3.weight(.semibold))
                    Text(exhibit.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    ForEach(exhibit.tags, id: \.self) { tag in
                        TagChip(text: tag, tint: exhibit.tint)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isHovering ? exhibit.tint.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: exhibit.tint.opacity(isHovering ? 0.28 : 0), radius: 18, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.015 : 1)
        .animation(.snappy(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
        .help("Open \(exhibit.title)")
    }
}

// MARK: - Colophon

private struct Colophon: View {
    private var linesOfSwift: Int? {
        Bundle.main.object(forInfoDictionaryKey: "MenagerieLinesOfSwift") as? Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            HStack(alignment: .top, spacing: 36) {
                Fact(value: "9", label: "interactive exhibits")
                if let linesOfSwift {
                    Fact(value: linesOfSwift.formatted(), label: "lines of Swift")
                }
                Fact(value: "0", label: "third-party dependencies")
                Fact(value: "100%", label: "on-device")
            }
            Text("Built with SwiftUI, AppKit, Metal, AVFoundation, NaturalLanguage and Swift Charts. Every algorithm lives in a portable engine library with its own test suite, and those tests pass on Linux too.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Fact: View {
        let value: String
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
