import Testing
@testable import notetaker

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
}
