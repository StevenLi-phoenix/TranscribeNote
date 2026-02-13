import Testing
import AVFoundation
@testable import notetaker

@Suite("Synthetic Buffer Injection")
struct SyntheticBufferInjectionTests {

    /// Helper to create a simple test buffer
    private func makeTestBuffer(frameCount: AVAudioFrameCount = 1024) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        return buffer
    }

    @Test func mockEngineReceivesSyntheticBuffers() {
        let engine = MockASREngine()
        let buffer = makeTestBuffer()

        engine.appendAudioBuffer(buffer)

        #expect(engine.appendedBufferCount == 1)
        #expect(engine.lastAppendedBuffer === buffer)
    }

    @Test func mockEngineCountsMultipleBuffers() {
        let engine = MockASREngine()

        for _ in 0..<10 {
            engine.appendAudioBuffer(makeTestBuffer())
        }

        #expect(engine.appendedBufferCount == 10)
    }

    @Test func noopEngineAcceptsSyntheticBuffers() {
        let engine = NoopASREngine()
        let buffer = makeTestBuffer()

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

        let buffer1 = makeTestBuffer()
        let buffer2 = makeTestBuffer(frameCount: 512)

        onAudioBuffer(buffer1)
        onAudioBuffer(buffer2)

        #expect(engine.appendedBufferCount == 2)
        #expect(engine.lastAppendedBuffer === buffer2)
    }
}
