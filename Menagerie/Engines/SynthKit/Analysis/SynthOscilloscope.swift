/// Oscilloscope triggering: finds where to start drawing so a periodic waveform stands still.
public enum SynthOscilloscope {
    /// Fills `output` with a window of `history` that begins at a rising zero crossing.
    ///
    /// The trigger has hysteresis (the signal must first dip below 5 % of its peak, so noise
    /// dithering around zero cannot fire it), and it picks the latest crossing that still leaves
    /// a full window after it. The crossing is located to sub-sample precision and the window is
    /// resampled from there, so the trace does not jitter by a sample from frame to frame.
    ///
    /// - Returns: `true` if a trigger was found. Otherwise the newest samples are copied as-is.
    @discardableResult
    public static func trigger(history: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) -> Bool {
        let n = output.count
        let h = history.count
        guard n > 0 else { return false }
        guard h >= n + 2 else {
            copyNewest(history, into: output)
            return false
        }

        var peak: Float = 0
        for x in history { peak = max(peak, abs(x)) }
        guard peak > 1e-4 else {
            copyNewest(history, into: output)
            return false
        }

        let threshold = 0.05 * peak
        var armed = false
        var crossing = -1.0
        for i in 1 ..< (h - n) {
            let x = history[i]
            if x < -threshold { armed = true }
            let previous = history[i - 1]
            if armed && previous < 0 && x >= 0 {
                crossing = Double(i - 1) + Double(-previous / (x - previous))
                armed = false
            }
        }
        guard crossing >= 0 else {
            copyNewest(history, into: output)
            return false
        }

        for k in 0 ..< n {
            let position = crossing + Double(k)
            let j = Int(position)
            let t = Float(position - Double(j))
            let a = history[j]
            let b = history[min(j + 1, h - 1)]
            output[k] = a + (b - a) * t
        }
        return true
    }

    private static func copyNewest(_ history: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) {
        let n = output.count
        let available = min(history.count, n)
        let padding = n - available
        for k in 0 ..< n {
            output[k] = k < padding ? 0 : history[history.count - available + k - padding]
        }
    }
}
