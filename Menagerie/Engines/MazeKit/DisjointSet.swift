/// Union–find over the integers `0..<count`, with union by size and path
/// halving, so every operation runs in near-constant amortised time.
///
/// Kruskal's algorithm uses it to reject walls whose removal would close a
/// loop. ``MazeGrid/topology`` uses it to count connected regions.
struct DisjointSet {
    private var parent: [Int]
    private var size: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        size = Array(repeating: 1, count: count)
    }

    /// The representative of the set containing `element`.
    mutating func find(_ element: Int) -> Int {
        var element = element
        while parent[element] != element {
            parent[element] = parent[parent[element]]
            element = parent[element]
        }
        return element
    }

    /// Merges the sets containing `a` and `b`. Returns `false` if they were
    /// already the same set.
    @discardableResult
    mutating func union(_ a: Int, _ b: Int) -> Bool {
        var rootA = find(a)
        var rootB = find(b)
        guard rootA != rootB else { return false }
        if size[rootA] < size[rootB] { swap(&rootA, &rootB) }
        parent[rootB] = rootA
        size[rootA] += size[rootB]
        return true
    }
}
