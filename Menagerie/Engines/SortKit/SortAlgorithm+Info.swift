/// Broad strategies for sorting, used to group algorithms.
public enum SortFamily: String, CaseIterable, Identifiable, Sendable {
    case exchange
    case insertion
    case selection
    case divideAndConquer
    case distribution
    case network

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .exchange: "Exchange"
        case .insertion: "Insertion"
        case .selection: "Selection"
        case .divideAndConquer: "Divide and Conquer"
        case .distribution: "Distribution"
        case .network: "Sorting Network"
        }
    }

    /// The family's algorithms, in declaration order.
    public var algorithms: [SortAlgorithm] {
        SortAlgorithm.allCases.filter { $0.family == self }
    }
}

/// How an algorithm's running time grows with the input size, coarsely.
public enum SortGrowth: Int, Comparable, Sendable {
    /// n, or n·k for a bounded key width k.
    case linear
    /// n log n.
    case linearithmic
    /// Between n log n and n², such as n log² n or n^1.25.
    case subquadratic
    /// n².
    case quadratic

    public static func < (lhs: SortGrowth, rhs: SortGrowth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Asymptotic costs of an algorithm, written for display without the
/// surrounding "O( )": `"n log n"`, `"n²"`.
public struct SortComplexity: Hashable, Sendable {
    public let best: String
    public let average: String
    public let worst: String
    /// Auxiliary memory beyond the array itself.
    public let memory: String
    /// The growth class of the average case.
    public let averageGrowth: SortGrowth
    /// Explains any symbol that needs it.
    public let note: String?

    public init(
        best: String,
        average: String,
        worst: String,
        memory: String,
        averageGrowth: SortGrowth,
        note: String? = nil
    ) {
        self.best = best
        self.average = average
        self.worst = worst
        self.memory = memory
        self.averageGrowth = averageGrowth
        self.note = note
    }
}

extension SortAlgorithm {
    /// The display name, like "Quick Sort".
    public var name: String {
        switch self {
        case .bubble: "Bubble Sort"
        case .cocktailShaker: "Cocktail Shaker Sort"
        case .gnome: "Gnome Sort"
        case .comb: "Comb Sort"
        case .insertion: "Insertion Sort"
        case .shell: "Shell Sort"
        case .selection: "Selection Sort"
        case .cycle: "Cycle Sort"
        case .heap: "Heap Sort"
        case .merge: "Merge Sort"
        case .quick: "Quick Sort"
        case .radixLSD: "Radix Sort (LSD)"
        case .bitonic: "Bitonic Sort"
        }
    }

    /// A compact name for tight spaces, like "Quick".
    public var shortName: String {
        switch self {
        case .bubble: "Bubble"
        case .cocktailShaker: "Cocktail"
        case .gnome: "Gnome"
        case .comb: "Comb"
        case .insertion: "Insertion"
        case .shell: "Shell"
        case .selection: "Selection"
        case .cycle: "Cycle"
        case .heap: "Heap"
        case .merge: "Merge"
        case .quick: "Quick"
        case .radixLSD: "Radix"
        case .bitonic: "Bitonic"
        }
    }

    public var family: SortFamily {
        switch self {
        case .bubble, .cocktailShaker, .gnome, .comb: .exchange
        case .insertion, .shell: .insertion
        case .selection, .cycle, .heap: .selection
        case .merge, .quick: .divideAndConquer
        case .radixLSD: .distribution
        case .bitonic: .network
        }
    }

    /// One sentence on how the algorithm works.
    public var summary: String {
        switch self {
        case .bubble:
            "Sweeps the array swapping out-of-order neighbours, so each pass floats the largest remaining value to the end."
        case .cocktailShaker:
            "Bubble sort in both directions: passes alternate, carrying large values right and small values left."
        case .gnome:
            "Walks forward while neighbours are in order and steps back with a swap whenever they aren't."
        case .comb:
            "Bubble sort over a gap that shrinks by 1.3 each pass, so small values stuck near the end move early."
        case .insertion:
            "Grows a sorted prefix, sinking each new value to the left until it meets a smaller one."
        case .shell:
            "Insertion sort over Ciura's shrinking gaps (…, 57, 23, 10, 4, 1), so values travel far in few moves."
        case .selection:
            "Scans the unsorted part for its minimum and swaps it into place: many comparisons, at most n − 1 swaps."
        case .cycle:
            "Counts the smaller values to find each element's final slot and swaps it straight there; every swap settles one element for good."
        case .heap:
            "Arranges the array into a max-heap, then repeatedly swaps the root to the end and sifts the new root down."
        case .merge:
            "Sorts each half recursively, then merges the two sorted halves through a buffer."
        case .quick:
            "Partitions around a median-of-three pivot, smaller values left and larger right, then sorts each side."
        case .radixLSD:
            "Never compares: deals values into four buckets by each base-4 digit, least significant first."
        case .bitonic:
            "A sorting network: a fixed schedule of compare-exchanges, blind to the data, built from bitonic merges."
        }
    }

    public var complexity: SortComplexity {
        switch self {
        case .bubble, .cocktailShaker, .gnome, .insertion:
            SortComplexity(best: "n", average: "n²", worst: "n²", memory: "1", averageGrowth: .quadratic)
        case .comb:
            SortComplexity(
                best: "n log n", average: "n²/2ᵖ", worst: "n²", memory: "1", averageGrowth: .subquadratic,
                note: "p is the number of gap reductions; in practice comb sort runs close to n log n."
            )
        case .shell:
            SortComplexity(
                best: "n log n", average: "≈ n¹·²⁵", worst: "unknown", memory: "1", averageGrowth: .subquadratic,
                note: "Ciura found these gaps by experiment, and their exact bounds are still unproven."
            )
        case .selection, .cycle:
            SortComplexity(best: "n²", average: "n²", worst: "n²", memory: "1", averageGrowth: .quadratic)
        case .heap:
            SortComplexity(best: "n log n", average: "n log n", worst: "n log n", memory: "1", averageGrowth: .linearithmic)
        case .merge:
            SortComplexity(best: "n log n", average: "n log n", worst: "n log n", memory: "n", averageGrowth: .linearithmic)
        case .quick:
            SortComplexity(
                best: "n log n", average: "n log n", worst: "n²", memory: "log n", averageGrowth: .linearithmic,
                note: "Median-of-three pivots make the quadratic worst case vanishingly rare."
            )
        case .radixLSD:
            SortComplexity(
                best: "n·k", average: "n·k", worst: "n·k", memory: "n", averageGrowth: .linear,
                note: "k is the number of base-4 digits in the largest value."
            )
        case .bitonic:
            SortComplexity(
                best: "n log² n", average: "n log² n", worst: "n log² n", memory: "log n", averageGrowth: .subquadratic
            )
        }
    }

    /// Stable sorts keep elements with equal keys in their original order.
    public var isStable: Bool {
        switch self {
        case .bubble, .cocktailShaker, .gnome, .insertion, .merge, .radixLSD: true
        case .comb, .shell, .selection, .cycle, .heap, .quick, .bitonic: false
        }
    }

    /// In-place sorts need no buffer proportional to the input (a recursion
    /// stack of O(log n) is allowed).
    public var isInPlace: Bool {
        switch self {
        case .merge, .radixLSD: false
        default: true
        }
    }

    /// Whether the algorithm orders elements by comparing them. Radix sort
    /// reads digits instead.
    public var isComparisonSort: Bool {
        self != .radixLSD
    }

    /// True for algorithms whose average running time grows as n².
    public var isQuadratic: Bool {
        complexity.averageGrowth == .quadratic
    }
}
