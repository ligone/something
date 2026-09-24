/// A growable array of plain values whose base address never moves while it
/// is being read.
///
/// The step kernel hands raw pointers to several worker threads at once. Swift
/// arrays can only lend a pointer inside a closure, so the world keeps its hot
/// data in these columns and reads their `base` directly. Only trivial element
/// types (`Float`, `UInt8`, `Int32`) are stored.
final class ParticleColumn<Element> {
    private(set) var base: UnsafeMutablePointer<Element>
    private(set) var capacity: Int
    private let filler: Element

    init(capacity: Int, filler: Element) {
        let size = max(capacity, 1)
        self.base = .allocate(capacity: size)
        self.base.initialize(repeating: filler, count: size)
        self.capacity = size
        self.filler = filler
    }

    deinit {
        base.deinitialize(count: capacity)
        base.deallocate()
    }

    /// Ensures room for `count` elements, keeping the first `preserved`.
    func reserve(_ count: Int, preserving preserved: Int) {
        guard count > capacity else { return }
        let newCapacity = max(count, capacity + capacity / 2)
        let newBase = UnsafeMutablePointer<Element>.allocate(capacity: newCapacity)
        let kept = min(preserved, capacity)
        newBase.initialize(from: base, count: kept)
        (newBase + kept).initialize(repeating: filler, count: newCapacity - kept)
        base.deinitialize(count: capacity)
        base.deallocate()
        base = newBase
        capacity = newCapacity
    }

    @inline(__always)
    subscript(index: Int) -> Element {
        get { base[index] }
        set { base[index] = newValue }
    }
}
