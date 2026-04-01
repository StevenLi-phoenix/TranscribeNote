import Testing
@testable import TranscribeNote

struct RingBufferTests {
    @Test func emptyBuffer() {
        let buffer = RingBuffer(capacity: 10)
        #expect(buffer.availableCount == 0)
        #expect(buffer.readAll().isEmpty)
        #expect(buffer.readLatest(count: 5).isEmpty)
    }

    @Test func writeAndReadAll() {
        let buffer = RingBuffer(capacity: 10)
        buffer.write([1.0, 2.0, 3.0])
        #expect(buffer.availableCount == 3)
        let data = buffer.readAll()
        #expect(data == [1.0, 2.0, 3.0])
    }

    @Test func readLatest() {
        let buffer = RingBuffer(capacity: 10)
        buffer.write([1.0, 2.0, 3.0, 4.0, 5.0])
        let latest = buffer.readLatest(count: 3)
        #expect(latest == [3.0, 4.0, 5.0])
    }

    @Test func readLatestMoreThanAvailable() {
        let buffer = RingBuffer(capacity: 10)
        buffer.write([1.0, 2.0])
        let latest = buffer.readLatest(count: 5)
        #expect(latest == [1.0, 2.0])
    }

    @Test func overflowWrap() {
        let buffer = RingBuffer(capacity: 4)
        buffer.write([1.0, 2.0, 3.0, 4.0])
        buffer.write([5.0, 6.0])
        #expect(buffer.availableCount == 4)
        let data = buffer.readAll()
        #expect(data == [3.0, 4.0, 5.0, 6.0])
    }

    @Test func reset() {
        let buffer = RingBuffer(capacity: 10)
        buffer.write([1.0, 2.0, 3.0])
        buffer.reset()
        #expect(buffer.availableCount == 0)
        #expect(buffer.readAll().isEmpty)
    }

    @Test func writeExactCapacity() {
        let buffer = RingBuffer(capacity: 3)
        buffer.write([1.0, 2.0, 3.0])
        #expect(buffer.availableCount == 3)
        #expect(buffer.readAll() == [1.0, 2.0, 3.0])
    }

    @Test func multipleWrites() {
        let buffer = RingBuffer(capacity: 10)
        buffer.write([1.0, 2.0])
        buffer.write([3.0, 4.0])
        #expect(buffer.availableCount == 4)
        #expect(buffer.readAll() == [1.0, 2.0, 3.0, 4.0])
    }

    // MARK: - Pointer-based write tests

    @Test func pointerWriteBasic() {
        let buffer = RingBuffer(capacity: 10)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0]
        samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: ptr.count)
        }
        #expect(buffer.availableCount == 4)
        #expect(buffer.readAll() == [1.0, 2.0, 3.0, 4.0])
    }

    @Test func pointerWriteWrapAround() {
        let buffer = RingBuffer(capacity: 4)
        // Fill to capacity via array write
        buffer.write([1.0, 2.0, 3.0, 4.0])
        #expect(buffer.availableCount == 4)

        // Pointer write that wraps around
        let extras: [Float] = [5.0, 6.0]
        extras.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: ptr.count)
        }
        #expect(buffer.availableCount == 4)
        #expect(buffer.readAll() == [3.0, 4.0, 5.0, 6.0])
    }

    @Test func pointerWriteOverCapacity() {
        let buffer = RingBuffer(capacity: 3)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
        samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: ptr.count)
        }
        #expect(buffer.availableCount == 3)
        #expect(buffer.readAll() == [3.0, 4.0, 5.0])
    }

    @Test func pointerWriteDelegation() {
        // Verify that array write and pointer write produce identical results
        let bufferA = RingBuffer(capacity: 6)
        let bufferB = RingBuffer(capacity: 6)
        let samples: [Float] = [10.0, 20.0, 30.0, 40.0, 50.0]

        // Array write
        bufferA.write(samples)

        // Pointer write
        samples.withUnsafeBufferPointer { ptr in
            bufferB.write(ptr.baseAddress!, count: ptr.count)
        }

        #expect(bufferA.availableCount == bufferB.availableCount)
        #expect(bufferA.readAll() == bufferB.readAll())

        // Now overflow both the same way
        let more: [Float] = [60.0, 70.0, 80.0]
        bufferA.write(more)
        more.withUnsafeBufferPointer { ptr in
            bufferB.write(ptr.baseAddress!, count: ptr.count)
        }

        #expect(bufferA.availableCount == bufferB.availableCount)
        #expect(bufferA.readAll() == bufferB.readAll())
    }
}
