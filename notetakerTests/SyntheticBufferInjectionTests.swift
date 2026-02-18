import Testing
import AVFoundation
@testable import notetaker

@Suite("Synthetic Buffer Injection")
struct SyntheticBufferInjectionTests {

    @Test func mockEngineReceivesSyntheticBuffers() {
        let engine = MockASREngine()
        let buffer = BufferFactory.silence()

        engine.appendAudioBuffer(buffer)

        #expect(engine.appendedBufferCount == 1)
        #expect(engine.lastAppendedBuffer === buffer)
    }

    @Test func mockEngineCountsMultipleBuffers() {
        let engine = MockASREngine()

        for _ in 0..<10 {
            engine.appendAudioBuffer(BufferFactory.silence())
        }

        #expect(engine.appendedBufferCount == 10)
    }

    @Test func noopEngineAcceptsSyntheticBuffers() {
        let engine = NoopASREngine()
        let buffer = BufferFactory.silence()

        // Should not crash
        engine.appendAudioBuffer(buffer)
        engine.appendAudioBuffer(buffer)
    }

    @Test func callbackWiringForwardsToEngine() {
        let engine = MockASREngine()
        // Simulate the pattern: onAudioBuffer callback → appendAudioBuffer
        let onAudioBuffer: (AVAudioPCMBuffer) -> Void = { buffer in
            engine.appendAudioBuffer(buffer)
        }

        let buffer1 = BufferFactory.silence()
        let buffer2 = BufferFactory.silence(frameCount: 512)

        onAudioBuffer(buffer1)
        onAudioBuffer(buffer2)

        #expect(engine.appendedBufferCount == 2)
        #expect(engine.lastAppendedBuffer === buffer2)
    }
}
