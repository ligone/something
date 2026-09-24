/// A power-of-two circular buffer with integer, linear and cubic reads.
///
/// The struct holds a pointer to heap storage that the owning effect allocates once and frees in
/// its `deinit`; copying the struct shares the storage, which lets hot loops work on a local copy.
struct SynthDelayLine {
    let buffer: UnsafeMutablePointer<Float>
    let mask: Int
    private(set) var writeIndex = 0

    /// Allocates a zeroed line holding at least `minimumLength` samples.
    init(minimumLength: Int) {
        var size = 4
        while size < minimumLength { size <<= 1 }
        buffer = .allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
        mask = size - 1
    }

    /// Number of samples the line can hold.
    var capacity: Int { mask + 1 }

    /// Frees the storage. Call exactly once, from the owner's `deinit`.
    func deallocate() {
        buffer.deallocate()
    }

    /// Zeroes the contents.
    func clear() {
        buffer.update(repeating: 0, count: capacity)
    }

    /// Appends a sample.
    @inline(__always)
    mutating func write(_ x: Float) {
        buffer[writeIndex] = x
        writeIndex = (writeIndex + 1) & mask
    }

    /// The sample written `delay` writes ago (1 is the most recent).
    @inline(__always)
    func read(_ delay: Int) -> Float {
        buffer[(writeIndex - delay) & mask]
    }

    /// Linearly interpolated read at a fractional delay ≥ 1.
    @inline(__always)
    func readLinear(_ delay: Float) -> Float {
        let whole = Int(delay)
        let fraction = delay - Float(whole)
        let a = read(whole)
        let b = read(whole + 1)
        return a + (b - a) * fraction
    }

    /// Four-point, third-order Hermite read at a fractional delay ≥ 2. Smoother than linear
    /// interpolation when the delay time is being modulated.
    @inline(__always)
    func readCubic(_ delay: Float) -> Float {
        let whole = Int(delay)
        let f = delay - Float(whole)
        let p0 = read(whole - 1)
        let p1 = read(whole)
        let p2 = read(whole + 1)
        let p3 = read(whole + 2)
        let c1 = 0.5 * (p2 - p0)
        let c2 = p0 - 2.5 * p1 + 2 * p2 - 0.5 * p3
        let c3 = 0.5 * (p3 - p0) + 1.5 * (p1 - p2)
        return ((c3 * f + c2) * f + c1) * f + p1
    }
}
