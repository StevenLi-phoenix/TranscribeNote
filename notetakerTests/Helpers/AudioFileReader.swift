import AVFoundation

/// Reads an audio file into a PCM buffer, optionally converting to a target format.
enum AudioFileReader {

    /// Read an entire audio file into a single `AVAudioPCMBuffer`, optionally converting to `targetFormat`.
    static func readFileAsBuffer(url: URL, targetFormat: AVAudioFormat? = nil) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw TestError("Failed to create source buffer")
        }
        try file.read(into: sourceBuffer)

        guard let targetFormat, sourceFormat != targetFormat else {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw TestError("Failed to create audio converter")
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw TestError("Failed to create output buffer")
        }

        var error: NSError?
        var hasProvided = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvided = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error {
            throw TestError("Conversion failed: \(error)")
        }

        return outputBuffer
    }

    /// Split a buffer into chunks of the given frame size.
    static func chunkBuffer(_ buffer: AVAudioPCMBuffer, frameSize: AVAudioFrameCount) -> [AVAudioPCMBuffer] {
        var chunks: [AVAudioPCMBuffer] = []
        let totalFrames = buffer.frameLength
        var offset: AVAudioFrameCount = 0

        while offset < totalFrames {
            let remaining = totalFrames - offset
            let chunkFrames = min(frameSize, remaining)

            guard let chunk = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: chunkFrames) else { break }
            chunk.frameLength = chunkFrames

            for ch in 0..<Int(buffer.format.channelCount) {
                let src = buffer.floatChannelData![ch].advanced(by: Int(offset))
                let dst = chunk.floatChannelData![ch]
                dst.update(from: src, count: Int(chunkFrames))
            }

            chunks.append(chunk)
            offset += chunkFrames
        }

        return chunks
    }
}
