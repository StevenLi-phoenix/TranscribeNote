import Testing
import AVFoundation

@Suite("BufferFactory")
struct BufferFactoryTests {

    @Test func sineWaveHasCorrectFrameCount() {
        let buffer = BufferFactory.sineWave(duration: 1.0, sampleRate: 48000.0)
        #expect(buffer.frameLength == 48000)
    }

    @Test func sineWaveHasNonZeroSamples() {
        let buffer = BufferFactory.sineWave()
        let data = buffer.floatChannelData![0]
        var hasNonZero = false
        for i in 0..<Int(buffer.frameLength) {
            if data[i] != 0 { hasNonZero = true; break }
        }
        #expect(hasNonZero, "Sine wave buffer should contain non-zero samples")
    }

    @Test func silenceBufferHasAllZeroSamples() {
        let buffer = BufferFactory.silence(frameCount: 512)
        let data = buffer.floatChannelData![0]
        var allZero = true
        for i in 0..<Int(buffer.frameLength) {
            if data[i] != 0 { allZero = false; break }
        }
        #expect(allZero, "Silence buffer should contain all zero samples")
    }

    @Test func defaultFormatMatchesExpectation() {
        let format = BufferFactory.defaultFormat(sampleRate: 44100.0, channels: 2)
        #expect(format.sampleRate == 44100.0)
        #expect(format.channelCount == 2)
    }

    @Test func sineWaveMultiChannel() {
        let buffer = BufferFactory.sineWave(channels: 2)
        #expect(buffer.format.channelCount == 2)
        // Both channels should have data
        for ch in 0..<2 {
            let data = buffer.floatChannelData![ch]
            var hasNonZero = false
            for i in 0..<Int(buffer.frameLength) {
                if data[i] != 0 { hasNonZero = true; break }
            }
            #expect(hasNonZero, "Channel \(ch) should have non-zero samples")
        }
    }
}
