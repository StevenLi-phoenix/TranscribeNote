import Testing
import Foundation
import AVFoundation
import Speech
@testable import notetaker

@Suite("File-to-ASR Integration", .serialized)
struct FileToASRIntegrationTests {

    // MARK: - Helpers

    /// Read an audio file into a single PCM buffer, optionally converting to a target format.
    private func readFileAsBuffer(url: URL, targetFormat: AVAudioFormat? = nil) throws -> AVAudioPCMBuffer {
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

    /// Chunk a buffer into smaller buffers of the given frame size.
    private func chunkBuffer(_ buffer: AVAudioPCMBuffer, frameSize: AVAudioFrameCount) -> [AVAudioPCMBuffer] {
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

    // MARK: - Tests

    /// Integration test: chunked file buffers → SpeechAnalyzerEngine.appendAudioBuffer() → transcription results.
    /// Requires Speech Recognition authorization.
    @Test(.timeLimit(.minutes(2)))
    func fileBuffersToASREngineProducesTranscription() async throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

        let engine = try SpeechAnalyzerEngine(locale: Locale(identifier: "en-US"))

        // Collect results
        let resultText = LockIsolated("")
        let gotFinal = LockIsolated(false)

        engine.onResult = { result in
            if result.isFinal {
                resultText.setValue(result.text)
                gotFinal.setValue(true)
            }
        }

        // Create a dummy AVAudioEngine to get the source format
        // SpeechAnalyzerEngine reads inputNode.outputFormat(forBus: 0)
        let dummyEngine = AVAudioEngine()
        let sourceFormat = dummyEngine.inputNode.outputFormat(forBus: 0)

        try engine.startRecognition(audioEngine: dummyEngine)

        // Wait for the engine to become ready (it fetches bestAvailableAudioFormat async)
        try await Task.sleep(for: .seconds(1))

        // Read and convert sample_speech.mp3 to match the source format
        let url = try sampleSpeechURL()
        let fullBuffer = try readFileAsBuffer(url: url, targetFormat: sourceFormat)

        // Chunk into 1024-frame buffers to simulate real tap behavior
        let chunks = chunkBuffer(fullBuffer, frameSize: 1024)
        #expect(chunks.count > 0, "Should have produced chunks from audio file")

        // Feed chunks with small delays
        for chunk in chunks {
            engine.appendAudioBuffer(chunk)
            try await Task.sleep(for: .milliseconds(5))
        }

        // Signal end of input
        engine.stopRecognition()

        // Wait for final result (may take time for speech recognition)
        try await waitForCondition(timeout: 30.0) {
            gotFinal.value
        }

        #expect(!resultText.value.isEmpty, "Transcription should produce non-empty text from file buffers")
    }

    /// Wiring test: FileAudioSource → MockASREngine.appendAudioBuffer().
    @Test(.timeLimit(.minutes(1)))
    func fileToMockEngineViaFileAudioSource() async throws {
        let mockEngine = MockASREngine()
        let source = FileAudioSource()

        let finished = LockIsolated(false)

        source.onAudioBuffer = { buffer in
            mockEngine.appendAudioBuffer(buffer)
        }
        source.onFinished = {
            finished.setValue(true)
        }

        let url = try sampleSpeechURL()
        try source.start(url: url)

        try await waitForCondition(timeout: 10.0) {
            finished.value
        }

        source.stop()

        #expect(mockEngine.appendedBufferCount > 0, "MockASREngine should have received buffers from FileAudioSource")
    }
}
