import Testing
import Foundation
import AVFoundation
import Speech
@testable import notetaker

@Suite("ASR Transcription – Real Audio (SpeechAnalyzer)", .serialized)
struct ASRTranscriptionTests {

    /// Read an audio file and produce an AsyncStream of AnalyzerInput buffers.
    private func audioInputStream(
        from url: URL,
        format targetFormat: AVAudioFormat
    ) throws -> AsyncStream<AnalyzerInput> {
        let buffer = try AudioFileReader.readFileAsBuffer(url: url, targetFormat: targetFormat)
        return AsyncStream { continuation in
            continuation.yield(AnalyzerInput(buffer: buffer))
            continuation.finish()
        }
    }

    /// Integration test: transcribes sample_speech.mp3 using SpeechAnalyzer.
    /// Requires Speech Recognition permission on the host machine.
    @Test(.enabled(if: SFSpeechRecognizer.authorizationStatus() == .authorized, "Requires speech recognition authorization"),
          .timeLimit(.minutes(2)))
    func transcribeAudioFileProducesResults() async throws {

        let locale = Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        let url = try sampleSpeechURL()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else { return }

        let inputStream = try audioInputStream(from: url, format: analyzerFormat)

        // Run analyzer and result collection concurrently
        async let analyzerRun: Void = {
            try await analyzer.start(inputSequence: inputStream)
        }()

        var finalText = ""
        for try await result in transcriber.results {
            if result.isFinal {
                finalText += String(result.text.characters)
            }
        }

        try await analyzerRun

        #expect(!finalText.isEmpty, "Transcription should produce non-empty text")
    }

    /// Verify our TranscriptResult model can be constructed from SpeechTranscriber data.
    @Test(.enabled(if: SFSpeechRecognizer.authorizationStatus() == .authorized, "Requires speech recognition authorization"),
          .timeLimit(.minutes(2)))
    func transcriptResultFromSpeechTranscriber() async throws {

        let locale = Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        let url = try sampleSpeechURL()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else { return }

        let inputStream = try audioInputStream(from: url, format: analyzerFormat)

        async let analyzerRun: Void = {
            try await analyzer.start(inputSequence: inputStream)
        }()

        var allText = ""
        for try await result in transcriber.results {
            if result.isFinal {
                allText += String(result.text.characters)
            }
        }

        try await analyzerRun

        let transcriptResult = TranscriptResult(
            text: allText,
            startTime: 0,
            endTime: 1.0,
            confidence: 1.0,
            language: "en-US",
            isFinal: true
        )

        #expect(transcriptResult.isFinal)
        #expect(!transcriptResult.text.isEmpty)
    }

    /// Verify volatile (partial) results are emitted with reportingOptions: [.volatileResults].
    @Test(.enabled(if: SFSpeechRecognizer.authorizationStatus() == .authorized, "Requires speech recognition authorization"),
          .timeLimit(.minutes(2)))
    func volatileResultsEmitted() async throws {

        let locale = Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        let url = try sampleSpeechURL()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else { return }

        let inputStream = try audioInputStream(from: url, format: analyzerFormat)

        async let analyzerRun: Void = {
            try await analyzer.start(inputSequence: inputStream)
        }()

        var volatileCount = 0
        var finalCount = 0

        for try await result in transcriber.results {
            if result.isFinal {
                finalCount += 1
            } else {
                volatileCount += 1
            }
        }

        try await analyzerRun

        #expect(finalCount > 0, "Should receive at least one final result")
        #expect(volatileCount > 0, "Should receive volatile (partial) results with .volatileResults option")
    }
}
