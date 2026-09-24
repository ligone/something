import Foundation

/// An in-place, iterative radix-2 Cooley–Tukey FFT for power-of-two sizes.
///
/// Twiddle factors and the bit-reversal permutation are computed once at init (in double
/// precision), so a transform does no allocation and no trigonometry.
public final class SynthFFT {
    /// Number of points.
    public let size: Int
    private let cosTable: UnsafeMutablePointer<Float>
    private let sinTable: UnsafeMutablePointer<Float>
    private let bitReversed: UnsafeMutablePointer<Int>

    /// Creates a transform of `size` points; `size` must be a power of two ≥ 2.
    public init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0, "SynthFFT size must be a power of two")
        self.size = size
        let half = size / 2
        cosTable = .allocate(capacity: half)
        sinTable = .allocate(capacity: half)
        for k in 0 ..< half {
            let angle = -2 * Double.pi * Double(k) / Double(size)
            (cosTable + k).initialize(to: Float(cos(angle)))
            (sinTable + k).initialize(to: Float(sin(angle)))
        }
        var bits = 0
        while 1 << bits < size { bits += 1 }
        bitReversed = .allocate(capacity: size)
        for i in 0 ..< size {
            var reversed = 0
            var value = i
            for _ in 0 ..< bits {
                reversed = (reversed << 1) | (value & 1)
                value >>= 1
            }
            (bitReversed + i).initialize(to: reversed)
        }
    }

    deinit {
        cosTable.deallocate()
        sinTable.deallocate()
        bitReversed.deallocate()
    }

    /// Forward transform, `X[k] = Σₙ x[n]·e^(−2πi·nk/N)`, in place on split real and imaginary
    /// arrays of `size` elements each.
    public func forward(real: UnsafeMutablePointer<Float>, imag: UnsafeMutablePointer<Float>) {
        for i in 0 ..< size {
            let j = bitReversed[i]
            if j > i {
                swap(&real[i], &real[j])
                swap(&imag[i], &imag[j])
            }
        }
        var half = 1
        while half < size {
            let stride = size / (half * 2)
            var start = 0
            while start < size {
                for k in 0 ..< half {
                    let wr = cosTable[k * stride]
                    let wi = sinTable[k * stride]
                    let i = start + k
                    let j = i + half
                    let tr = wr * real[j] - wi * imag[j]
                    let ti = wr * imag[j] + wi * real[j]
                    real[j] = real[i] - tr
                    imag[j] = imag[i] - ti
                    real[i] += tr
                    imag[i] += ti
                }
                start += half * 2
            }
            half *= 2
        }
    }

    /// Forward transform of Swift arrays (each must hold exactly `size` elements).
    public func forward(real: inout [Float], imag: inout [Float]) {
        precondition(real.count == size && imag.count == size, "SynthFFT expects \(size) samples")
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                if let r = re.baseAddress, let i = im.baseAddress {
                    forward(real: r, imag: i)
                }
            }
        }
    }
}
