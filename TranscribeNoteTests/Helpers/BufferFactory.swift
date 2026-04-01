import AVFoundation

enum BufferFactory {
    /// Create an AVAudioPCMBuffer filled with a sine wave.
    static func sineWave(
        frequency: Double = 440.0,
        duration: TimeInterval = 0.5,
        sampleRate: Double = 48000.0,
        channels: AVAudioChannelCount = 1
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for ch in 0..<Int(channels) {
            let channelData = buffer.floatChannelData![ch]
            for i in 0..<Int(frameCount) {
                channelData[i] = Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
            }
        }
        return buffer
    }

    /// Create an AVAudioPCMBuffer filled with silence (all zeros).
    static func silence(
        frameCount: AVAudioFrameCount = 1024,
        sampleRate: Double = 48000.0,
        channels: AVAudioChannelCount = 1
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        // Float buffers are zero-initialized by default
        return buffer
    }

    /// Create a standard AVAudioFormat for testing.
    static func defaultFormat(
        sampleRate: Double = 48000.0,
        channels: AVAudioChannelCount = 1
    ) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    }
}
