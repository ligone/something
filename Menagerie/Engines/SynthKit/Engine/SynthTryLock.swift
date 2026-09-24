import Foundation

/// A mutex that the real-time audio thread only ever *tries* to take.
///
/// SynthKit may only use the standard library and Foundation, and on macOS 14 the standard
/// library offers no atomics (`Synchronization.Atomic` needs macOS 15). A lock-free ring with
/// unsynchronized index publication is not safe on Apple silicon: ARM may reorder stores, so a
/// reader could see a new index before the data it guards. A POSIX mutex gives correct
/// acquire/release ordering on every architecture, and `pthread_mutex_trylock` never blocks:
/// if the UI happens to hold the lock, the audio thread simply skips that exchange and retries
/// on the next buffer, a few milliseconds later. The UI side takes the lock normally; the audio
/// thread's critical sections are a handful of copies, so it waits at most microseconds.
///
/// The mutex lives in its own heap allocation because a `pthread_mutex_t` must never move.
final class SynthTryLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    init() {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deinitialize(count: 1)
        mutex.deallocate()
    }

    /// Blocks until the lock is acquired. Never call this on the audio thread.
    @inline(__always)
    func lock() {
        pthread_mutex_lock(mutex)
    }

    /// Acquires the lock if it is free; never blocks.
    @inline(__always)
    func tryLock() -> Bool {
        pthread_mutex_trylock(mutex) == 0
    }

    @inline(__always)
    func unlock() {
        pthread_mutex_unlock(mutex)
    }
}
