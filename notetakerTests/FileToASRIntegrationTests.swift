import Testing
import Foundation
import AVFoundation
import Speech
@testable import notetaker

@Suite("File-to-ASR Integration", .serialized)
struct FileToASRIntegrationTests {

    // MARK: - Tests

    /// Integration test: chunked file buffers → SpeechAnalyzerEngine.appendAudioBuffer() → transcription results.
    /// Requires Speech Recognition authorization.
    @Test(.enabled(if: SFSpeechRecognizer.authorizationStatus() == .authorized, "Requires speech recognition authorization"),
          .timeLimit(.minutes(2)))
    func fileBuffersToASREngineProducesTranscription() async throws {

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
        let fullBuffer = try AudioFileReader.readFileAsBuffer(url: url, targetFormat: sourceFormat)

        // Chunk into 1024-frame buffers to simulate real tap behavior
        let chunks = AudioFileReader.chunkBuffer(fullBuffer, frameSize: 1024)
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
