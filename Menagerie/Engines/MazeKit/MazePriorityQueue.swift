/// A min-priority queue backed by an implicit binary heap stored in an array.
///
/// `push` and `pop` run in O(log n) and `peek` in O(1). Dijkstra's
/// algorithm, A* and greedy best-first search all keep their frontier in one.
public struct MazePriorityQueue<Element: Comparable> {
    private var heap: [Element] = []

    public init() {}

    /// Builds a queue from any sequence in O(n) using Floyd's bottom-up heapify.
    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        heap = Array(elements)
        var index = heap.count / 2 - 1
        while index >= 0 {
            siftDown(from: index)
            index -= 1
        }
    }

    /// The number of queued elements.
    public var count: Int { heap.count }

    /// Whether the queue is empty.
    public var isEmpty: Bool { heap.isEmpty }

    /// The smallest element, without removing it.
    public func peek() -> Element? { heap.first }

    /// Reserves storage for at least `capacity` elements.
    public mutating func reserveCapacity(_ capacity: Int) {
        heap.reserveCapacity(capacity)
    }

    /// Adds an element.
    public mutating func push(_ element: Element) {
        heap.append(element)
        siftUp(from: heap.count - 1)
    }

    /// Removes and returns the smallest element.
    @discardableResult
    public mutating func pop() -> Element? {
        guard let last = heap.popLast() else { return nil }
        guard !heap.isEmpty else { return last }
        let top = heap[0]
        heap[0] = last
        siftDown(from: 0)
        return top
    }

    private mutating func siftUp(from index: Int) {
        let element = heap[index]
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard element < heap[parent] else { break }
            heap[child] = heap[parent]
            child = parent
        }
        heap[child] = element
    }

    private mutating func siftDown(from index: Int) {
        let element = heap[index]
        let count = heap.count
        var parent = index
        while true {
            let left = 2 * parent + 1
            guard left < count else { break }
            let right = left + 1
            let smaller = right < count && heap[right] < heap[left] ? right : left
            guard heap[smaller] < element else { break }
            heap[parent] = heap[smaller]
            parent = smaller
        }
        heap[parent] = element
    }
}

extension MazePriorityQueue: Sendable where Element: Sendable {}
