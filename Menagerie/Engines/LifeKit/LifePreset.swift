/// A named rule set that is known to grow something beautiful.
///
/// The matrices were found by simulating a couple of hundred random and
/// structured candidates headlessly at a density of about 2,000 particles per
/// unit area, measuring how they cluster, spin and travel, and then picking the
/// most striking by eye.
public struct LifePreset: Hashable, Sendable, Identifiable {
    /// The display name, which is also the identity.
    public let name: String
    /// One sentence describing what emerges.
    public let summary: String
    /// Who attracts whom; this also fixes the number of species.
    public let matrix: SpeciesMatrix
    /// The physical constants the matrix was tuned with.
    public let rules: LifeRules

    public var id: String { name }

    /// Creates a preset.
    public init(name: String, summary: String, matrix: SpeciesMatrix, rules: LifeRules = LifeRules()) {
        self.name = name
        self.summary = summary
        self.matrix = matrix
        self.rules = rules
    }

    /// Every built-in preset, in menu order.
    public static let all: [LifePreset] = [pondLife, cells, snakes, swarm, galaxies, chains, blossoms]

    /// Finds a built-in preset by name.
    public static func named(_ name: String) -> LifePreset? {
        all.first { $0.name == name }
    }

    /// A restless microscope slide: segmented worms, green crescents and
    /// membrane-wrapped blobs that never quite settle.
    public static let pondLife = LifePreset(
        name: "Pond Life",
        summary: "Worms, crescents and blobs jostle like life under a microscope.",
        matrix: SpeciesMatrix(rows: [
            [-0.97, -0.59, -0.92, 0.94, -0.19],
            [-0.76, 0.88, -0.09, 0.13, 0.51],
            [0.02, 0.24, -0.03, 0.32, -0.99],
            [0.48, -0.50, -0.99, -0.05, 0.09],
            [-0.96, -0.05, -0.92, -0.96, -0.44],
        ])
    )

    /// Nuclei that gather rings of other species around themselves, adrift in
    /// a field of small colonies.
    public static let cells = LifePreset(
        name: "Cells",
        summary: "Nuclei wrap themselves in membranes made of other species.",
        matrix: SpeciesMatrix(rows: [
            [0.96, 0.89, -0.75, 0.70, 0.53],
            [0.78, -0.01, -0.25, 0.71, -0.88],
            [0.91, -0.56, -0.75, -0.07, -0.95],
            [0.03, 0.70, 0.90, 0.54, -0.88],
            [0.17, -0.39, -0.39, -0.63, -0.53],
        ])
    )

    /// Long trains of segments that race across the dish and swallow what
    /// they meet.
    public static let snakes = LifePreset(
        name: "Snakes",
        summary: "Segmented trains race across the dish, hunting as they go.",
        matrix: SpeciesMatrix(rows: [
            [0.15, -0.56, -0.01, 0.85, -0.09],
            [0.86, 0.41, 0.29, -0.91, -0.20],
            [-0.82, -0.43, 0.06, -0.22, 0.80],
            [-0.47, 0.91, -0.38, 0.94, 0.00],
            [-0.74, 0.21, 0.26, 0.86, -0.62],
        ])
    )

    /// Three species in a lopsided chase: tadpoles with bright heads swim
    /// through a drifting sea of the third.
    public static let swarm = LifePreset(
        name: "Swarm",
        summary: "Schools of tadpoles swim through a drifting sea.",
        matrix: SpeciesMatrix(rows: [
            [-0.15, -0.10, 0.89],
            [0.33, 0.48, -0.02],
            [-0.46, 0.60, 0.79],
        ])
    )

    /// Every species is drawn to itself and chases the next one round a ring,
    /// so each cluster turns into a spinning pinwheel.
    public static let galaxies = LifePreset(
        name: "Galaxies",
        summary: "Each species chases the next, so every cluster spins.",
        matrix: .cyclic(speciesCount: 4, own: 0.7, next: 0.8, previous: 0.15, others: 0.15),
        rules: LifeRules(frictionHalfLife: 0.05)
    )

    /// Species that love themselves, like their two neighbors a little and
    /// shun everyone else, which links them into rainbow chains.
    public static let chains = LifePreset(
        name: "Chains",
        summary: "Neighbors bond and strangers repel, so rainbow chains crystallize.",
        matrix: .cyclic(speciesCount: 6, own: 1, next: 0.2, previous: 0.2, others: -1)
    )

    /// The chains rule without the repulsion: the segments curl up into
    /// six-petaled rosettes and short caterpillars.
    public static let blossoms = LifePreset(
        name: "Blossoms",
        summary: "Six-petaled rosettes and caterpillars settle into a garden.",
        matrix: .cyclic(speciesCount: 6, own: 1, next: 0.2, previous: 0.2, others: 0)
    )
}
