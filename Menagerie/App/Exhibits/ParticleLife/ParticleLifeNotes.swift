extension ExhibitNotes {
    static let particleLife = ExhibitNotes(
        lede: "Thousands of particles, a handful of colors and one small table of likes and dislikes. From those rules alone, cells, worms and spinning galaxies assemble themselves in real time.",
        sections: [
            .init(
                title: "One force, two regimes",
                body: "Particles closer than the interaction radius *r* feel each other. Inside **β·r** (β = 0.3) a universal push keeps them from overlapping; beyond it, a triangular bump pulls or pushes with the strength of the matrix entry `a[i][j]`. Because `a[i][j]` need not equal `a[j][i]`, red can chase green while green flees red: the broken symmetry that keeps everything moving."
            ),
            .init(
                title: "Friction as a half-life",
                body: "Friction multiplies every velocity by `0.5^(dt / t½)` per step, so damping is the same at any frame rate or time scale. Integration is semi-implicit Euler: update the velocity from the forces, then move with the *new* velocity. That ordering is far more stable than plain Euler against stiff short-range repulsion. The world is a torus, so nothing ever meets a wall."
            ),
            .init(
                title: "Neighbors in a grid",
                body: "Comparing every pair of 6,000 particles would mean 36 million checks a step. Instead, a counting sort bins particles into cells one radius wide, so every neighbor lies in the surrounding 3 × 3 block. Adjacent cells sit side by side in memory, so each row of the block is one contiguous run, and the torus's seams become precomputed offsets instead of branches."
            ),
            .init(
                title: "Eight lanes, every core",
                body: "Forces are gathered, never scattered: each particle reads its neighbors and writes only its own state, so `DispatchQueue.concurrentPerform` splits the work into chunks with no locks. The inner loop tests eight candidates at once with `SIMD8<Float>` and masks rather than `if`s, since about a third fall inside the radius in no predictable pattern. Results are identical, bit for bit, on any number of cores."
            ),
            .init(
                title: "Where the presets came from",
                body: "The presets were found by simulating a couple of hundred random and structured matrices headlessly, scoring each for clustering, spin and speed, then judging the best by eye. **Galaxies** is a ring in which every species chases the next, so each cluster spins; **Chains** bonds neighbors and repels strangers. **Mutate** explores the space around any rule set."
            ),
        ]
    )
}
