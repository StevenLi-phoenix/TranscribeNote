import Foundation
import os

/// Thread-safe circular buffer for audio samples.
/// Designed for audio capture pipeline — `nonisolated` to avoid actor hops on audio threads.
nonisolated final class RingBuffer: @unchecked Sendable {
    private nonisolated(unsafe) let buffer: UnsafeMutableBufferPointer<Float>
    private let capacity: Int
    private let lock: OSAllocatedUnfairLock<State>

    private struct State: Sendable {
        var writeIndex: Int = 0
        var availableCount: Int = 0
    }

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = .allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0)
        self.lock = OSAllocatedUnfairLock(initialState: State())
    }

    deinit {
        buffer.deallocate()
    }

    var availableCount: Int {
        lock.withLock { $0.availableCount }
    }

    func write(_ samples: [Float]) {
        lock.withLock { state in
            for sample in samples {
                buffer[state.writeIndex] = sample
                state.writeIndex = (state.writeIndex + 1) % capacity
                state.availableCount = min(state.availableCount + 1, capacity)
            }
        }
    }

    func readLatest(count: Int) -> [Float] {
        lock.withLock { state in
            let readCount = min(count, state.availableCount)
            guard readCount > 0 else { return [] }

            let startIndex = (state.writeIndex - readCount + capacity) % capacity
            var result = [Float]()
            result.reserveCapacity(readCount)

            for i in 0..<readCount {
                result.append(buffer[(startIndex + i) % capacity])
            }
            return result
        }
    }

    func readAll() -> [Float] {
        lock.withLock { state in
            guard state.availableCount > 0 else { return [] }

            let startIndex = (state.writeIndex - state.availableCount + capacity) % capacity
            var result = [Float]()
            result.reserveCapacity(state.availableCount)

            for i in 0..<state.availableCount {
                result.append(buffer[(startIndex + i) % capacity])
            }
            return result
        }
    }

    func reset() {
        lock.withLock { state in
            state.writeIndex = 0
            state.availableCount = 0
        }
    }
}
