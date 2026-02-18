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
        precondition(capacity > 0, "RingBuffer capacity must be greater than 0")
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

    /// Bulk write from a raw pointer using memcpy with wrap-around handling.
    func write(_ pointer: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        lock.withLock { state in
            let basePtr = buffer.baseAddress!

            if count >= capacity {
                // Only the last `capacity` samples matter — single memcpy
                let offset = count - capacity
                memcpy(basePtr, pointer.advanced(by: offset), capacity * MemoryLayout<Float>.size)
                state.writeIndex = 0
                state.availableCount = capacity
            } else {
                let firstChunk = min(count, capacity - state.writeIndex)
                let secondChunk = count - firstChunk

                memcpy(basePtr.advanced(by: state.writeIndex), pointer, firstChunk * MemoryLayout<Float>.size)
                if secondChunk > 0 {
                    memcpy(basePtr, pointer.advanced(by: firstChunk), secondChunk * MemoryLayout<Float>.size)
                }

                state.writeIndex = (state.writeIndex + count) % capacity
                state.availableCount = min(state.availableCount + count, capacity)
            }
        }
    }

    func write(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else { return }
            write(baseAddress, count: bufferPointer.count)
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
