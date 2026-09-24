import SwiftUI

/// Every screen in the app. The order here is the order of the sidebar and of
/// the ⌘0–⌘9 shortcuts.
enum Exhibit: String, CaseIterable, Identifiable, Hashable {
    case welcome
    case fractals
    case pathTracer
    case particleLife
    case mazeLab
    case calculus
    case connectFour
    case languageLab
    case sorting
    case synthesizer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .fractals: "Fractal Explorer"
        case .pathTracer: "Path Tracer"
        case .particleLife: "Particle Life"
        case .mazeLab: "Maze Lab"
        case .calculus: "Calculus Workbench"
        case .connectFour: "Connect Four"
        case .languageLab: "Language Lab"
        case .sorting: "Sound of Sorting"
        case .synthesizer: "Synthesizer"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: "A cabinet of computational curiosities"
        case .fractals: "Infinite zoom on the GPU"
        case .pathTracer: "Physically based light, one ray at a time"
        case .particleLife: "Artificial life from six numbers a pair"
        case .mazeLab: "Carve mazes, then watch search think"
        case .calculus: "Symbolic derivatives, roots and Taylor series"
        case .connectFour: "Play a bitboard alpha-beta engine"
        case .languageLab: "On-device linguistics"
        case .sorting: "Hear algorithms put the world in order"
        case .synthesizer: "A polyphonic synth written from scratch"
        }
    }

    /// One or two sentences for the welcome screen's cards.
    var summary: String {
        switch self {
        case .welcome:
            "Start here."
        case .fractals:
            "Dive into the Mandelbrot and Julia sets with a Metal shader that emulates 64-bit floats to zoom a billion times deeper."
        case .pathTracer:
            "A progressive Monte Carlo renderer with glass, metal, soft shadows and depth of field, spread across every CPU core."
        case .particleLife:
            "Thousands of particles follow a handful of attraction rules and organize into cells, worms and swarms."
        case .mazeLab:
            "Generate mazes five different ways, paint walls and mud, and race BFS, Dijkstra, A* and friends."
        case .calculus:
            "Type any function to get its exact derivative, its roots and extrema, integrals, and Taylor approximations."
        case .connectFour:
            "A negamax search with a transposition table that shows its evaluation of every column as it thinks."
        case .languageLab:
            "Sentiment, entities, parts of speech, word analogies and readability, computed on device with nothing sent to a server."
        case .sorting:
            "Ten sorting algorithms, visualized and sonified: every comparison sounds a pitch."
        case .synthesizer:
            "Band-limited oscillators, a zero-delay-feedback filter, envelopes and effects. Play it with your keyboard."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .fractals: "sparkles"
        case .pathTracer: "camera.aperture"
        case .particleLife: "atom"
        case .mazeLab: "point.topleft.down.curvedto.point.bottomright.up"
        case .calculus: "function"
        case .connectFour: "circle.grid.3x3.fill"
        case .languageLab: "text.bubble"
        case .sorting: "chart.bar.fill"
        case .synthesizer: "pianokeys"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: .indigo
        case .fractals: Color(red: 0.72, green: 0.36, blue: 0.98)
        case .pathTracer: Color(red: 1.00, green: 0.58, blue: 0.20)
        case .particleLife: Color(red: 0.20, green: 0.84, blue: 0.72)
        case .mazeLab: Color(red: 0.36, green: 0.80, blue: 0.36)
        case .calculus: Color(red: 0.26, green: 0.56, blue: 1.00)
        case .connectFour: Color(red: 0.96, green: 0.30, blue: 0.34)
        case .languageLab: Color(red: 1.00, green: 0.38, blue: 0.66)
        case .sorting: Color(red: 1.00, green: 0.80, blue: 0.18)
        case .synthesizer: Color(red: 0.22, green: 0.78, blue: 0.98)
        }
    }

    /// The technologies each exhibit leans on, shown as chips.
    var tags: [String] {
        switch self {
        case .welcome: []
        case .fractals: ["Metal", "GPU shaders", "Double-float math"]
        case .pathTracer: ["Monte Carlo", "Multithreading", "Optics"]
        case .particleLife: ["Emergence", "Spatial hashing", "Canvas"]
        case .mazeLab: ["Graph search", "Spanning trees", "Swift Charts"]
        case .calculus: ["Parsing", "Computer algebra", "Numerics"]
        case .connectFour: ["Game trees", "Bitboards", "Alpha-beta"]
        case .languageLab: ["NaturalLanguage", "Embeddings", "NLP"]
        case .sorting: ["Algorithms", "AVAudioEngine", "Sonification"]
        case .synthesizer: ["DSP", "Real-time audio", "Accelerate"]
        }
    }

    var group: ExhibitGroup? {
        switch self {
        case .welcome: nil
        case .fractals, .pathTracer, .particleLife: .see
        case .mazeLab, .calculus, .connectFour, .languageLab: .think
        case .sorting, .synthesizer: .hear
        }
    }

    /// The "How it works" notes shown under each exhibit's controls.
    var notes: ExhibitNotes {
        switch self {
        case .welcome: .welcome
        case .fractals: .fractals
        case .pathTracer: .pathTracer
        case .particleLife: .particleLife
        case .mazeLab: .mazeLab
        case .calculus: .calculus
        case .connectFour: .connectFour
        case .languageLab: .languageLab
        case .sorting: .sorting
        case .synthesizer: .synthesizer
        }
    }

    /// ⌘0 for Welcome, ⌘1–⌘9 for the exhibits.
    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character(String(Exhibit.allCases.firstIndex(of: self)!)))
    }

    var next: Exhibit {
        let all = Exhibit.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var previous: Exhibit {
        let all = Exhibit.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }
}

/// The sidebar sections.
enum ExhibitGroup: String, CaseIterable, Identifiable {
    case see, think, hear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .see: "See"
        case .think: "Think"
        case .hear: "Hear"
        }
    }

    var blurb: String {
        switch self {
        case .see: "Light, geometry and life, computed live on the GPU and across every CPU core."
        case .think: "Search, symbolic reasoning, game strategy and language."
        case .hear: "Sound synthesized sample by sample, in real time."
        }
    }

    var exhibits: [Exhibit] {
        Exhibit.allCases.filter { $0.group == self }
    }
}

/// Explanatory copy for an exhibit's "How it works" panel.
struct ExhibitNotes {
    struct Section: Hashable {
        var title: String
        /// Supports inline Markdown: **bold**, *italic*, `code` and links.
        var body: String
    }

    /// One or two sentences that open the panel.
    var lede: String
    var sections: [Section]
}

extension ExhibitNotes {
    static let welcome = ExhibitNotes(
        lede: "Menagerie is a gallery of small, complete programs. Each exhibit runs entirely on your Mac, with no network access and no third-party code.",
        sections: []
    )
}
