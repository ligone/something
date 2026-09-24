/// One node of a flattened bounding volume hierarchy.
///
/// Nodes are stored depth-first, so an interior node's first child directly
/// follows it. Only the second child's index needs storing.
struct BVHNode {
    var lower: Vec3
    var upper: Vec3
    /// For a leaf, the index of its first primitive. For an interior node, the
    /// index of its second child.
    var offset: Int32
    /// The number of primitives in a leaf, or 0 for an interior node.
    var count: Int32
    /// The split axis of an interior node, used to visit the nearer child first.
    var axis: Int32
}

/// Builds a BVH with the binned surface area heuristic (Wald 2007).
///
/// The SAH estimates the cost of a split by the probability that a ray
/// entering the parent also enters each child, which is proportional to
/// surface area, times the work waiting inside that child.
enum BVHBuilder {
    struct Item {
        var lower: Vec3
        var upper: Vec3
        var centroid: Vec3
        var index: Int
    }

    static let binCount = 12
    static let maxLeafSize = 6
    /// Deep enough for any sensible scene, and within the kernel's fixed
    /// 64-entry traversal stack.
    static let maxDepth = 48

    /// Returns the flattened nodes and the primitive order the leaves refer to.
    static func build(_ items: [Item]) -> (nodes: [BVHNode], order: [Int]) {
        guard !items.isEmpty else { return ([], []) }
        var items = items
        var nodes: [BVHNode] = []
        nodes.reserveCapacity(items.count * 2)
        _ = buildNode(&items, start: 0, end: items.count, depth: 0, nodes: &nodes)
        return (nodes, items.map { $0.index })
    }

    private static func halfArea(_ lower: Vec3, _ upper: Vec3) -> Float {
        let e = upper - lower
        if e.x < 0 || e.y < 0 || e.z < 0 { return 0 }
        return e.x * e.y + e.y * e.z + e.z * e.x
    }

    private static func buildNode(_ items: inout [Item], start: Int, end: Int, depth: Int, nodes: inout [BVHNode]) -> Int {
        var lower = Vec3(repeating: .infinity)
        var upper = Vec3(repeating: -.infinity)
        var centroidLower = Vec3(repeating: .infinity)
        var centroidUpper = Vec3(repeating: -.infinity)
        for i in start..<end {
            lower = pointwiseMin(lower, items[i].lower)
            upper = pointwiseMax(upper, items[i].upper)
            centroidLower = pointwiseMin(centroidLower, items[i].centroid)
            centroidUpper = pointwiseMax(centroidUpper, items[i].centroid)
        }

        let nodeIndex = nodes.count
        let count = end - start
        nodes.append(BVHNode(lower: lower, upper: upper, offset: Int32(start), count: Int32(count), axis: 0))
        if count == 1 || depth >= maxDepth { return nodeIndex }

        let extent = centroidUpper - centroidLower
        var axis = 0
        if extent.y > extent[axis] { axis = 1 }
        if extent.z > extent[axis] { axis = 2 }

        var mid = start + count / 2
        if extent[axis] > 1e-9 {
            guard let split = bestSplit(items, start: start, end: end, axis: axis,
                                        centroidMin: centroidLower[axis], centroidExtent: extent[axis],
                                        parentArea: halfArea(lower, upper)) else {
                return nodeIndex
            }
            if split.cost >= Float(count) && count <= maxLeafSize { return nodeIndex }
            mid = partition(&items, start: start, end: end) { item in
                binIndex(item.centroid[axis], min: centroidLower[axis], extent: extent[axis]) <= split.bin
            }
            if mid == start || mid == end { mid = start + count / 2 }
        } else if count <= maxLeafSize {
            // All centroids coincide, so no split can separate them.
            return nodeIndex
        }

        _ = buildNode(&items, start: start, end: mid, depth: depth + 1, nodes: &nodes)
        let second = buildNode(&items, start: mid, end: end, depth: depth + 1, nodes: &nodes)
        nodes[nodeIndex].offset = Int32(second)
        nodes[nodeIndex].count = 0
        nodes[nodeIndex].axis = Int32(axis)
        return nodeIndex
    }

    private static func binIndex(_ value: Float, min: Float, extent: Float) -> Int {
        let scaled = (value - min) / extent * Float(binCount)
        return Swift.min(binCount - 1, Swift.max(0, Int(scaled)))
    }

    /// Evaluates the SAH at every bin boundary and returns the cheapest split:
    /// primitives in bins `0...bin` go left. The cost is in units of one
    /// primitive intersection, and a node traversal counts as one unit too.
    private static func bestSplit(_ items: [Item], start: Int, end: Int, axis: Int, centroidMin: Float,
                                  centroidExtent: Float, parentArea: Float) -> (bin: Int, cost: Float)? {
        var binLower = [Vec3](repeating: Vec3(repeating: .infinity), count: binCount)
        var binUpper = [Vec3](repeating: Vec3(repeating: -.infinity), count: binCount)
        var binItems = [Int](repeating: 0, count: binCount)
        for i in start..<end {
            let b = binIndex(items[i].centroid[axis], min: centroidMin, extent: centroidExtent)
            binItems[b] += 1
            binLower[b] = pointwiseMin(binLower[b], items[i].lower)
            binUpper[b] = pointwiseMax(binUpper[b], items[i].upper)
        }

        // Sweep from the right to collect suffix areas and counts.
        var rightArea = [Float](repeating: 0, count: binCount)
        var rightCount = [Int](repeating: 0, count: binCount)
        var accLower = Vec3(repeating: .infinity)
        var accUpper = Vec3(repeating: -.infinity)
        var accCount = 0
        for b in stride(from: binCount - 1, to: 0, by: -1) {
            accLower = pointwiseMin(accLower, binLower[b])
            accUpper = pointwiseMax(accUpper, binUpper[b])
            accCount += binItems[b]
            rightArea[b] = halfArea(accLower, accUpper)
            rightCount[b] = accCount
        }

        var best: (bin: Int, cost: Float)?
        accLower = Vec3(repeating: .infinity)
        accUpper = Vec3(repeating: -.infinity)
        accCount = 0
        let inverseArea = parentArea > 0 ? 1 / parentArea : 0
        for b in 0..<(binCount - 1) {
            accLower = pointwiseMin(accLower, binLower[b])
            accUpper = pointwiseMax(accUpper, binUpper[b])
            accCount += binItems[b]
            let leftCount = accCount
            let rightItems = rightCount[b + 1]
            guard leftCount > 0, rightItems > 0 else { continue }
            let leftCost = halfArea(accLower, accUpper) * Float(leftCount)
            let rightCost = rightArea[b + 1] * Float(rightItems)
            let cost = 1 + (leftCost + rightCost) * inverseArea
            if best == nil || cost < best!.cost { best = (b, cost) }
        }
        return best
    }

    /// Moves the elements that satisfy `belongsLeft` to the front and returns
    /// the index where the rest begin.
    private static func partition(_ items: inout [Item], start: Int, end: Int, _ belongsLeft: (Item) -> Bool) -> Int {
        var i = start
        var j = end - 1
        while i <= j {
            if belongsLeft(items[i]) {
                i += 1
            } else {
                items.swapAt(i, j)
                j -= 1
            }
        }
        return i
    }
}
