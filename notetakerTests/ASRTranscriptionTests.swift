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
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw TestError("Failed to create source buffer")
        }
        try file.read(into: sourceBuffer)

        return AsyncStream { continuation in
            if sourceFormat == targetFormat {
                continuation.yield(AnalyzerInput(buffer: sourceBuffer))
            } else if let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) {
                let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1
                if let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) {
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
                    if error == nil {
                        continuation.yield(AnalyzerInput(buffer: outputBuffer))
                    }
                }
            }
            continuation.finish()
        }
    }

    /// Integration test: transcribes sample_speech.mp3 using SpeechAnalyzer.
    /// Requires Speech Recognition permission on the host machine.
    @Test(.timeLimit(.minutes(2)))
    func transcribeAudioFileProducesResults() async throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

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
    @Test(.timeLimit(.minutes(2)))
    func transcriptResultFromSpeechTranscriber() async throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

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
    @Test(.timeLimit(.minutes(2)))
    func volatileResultsEmitted() async throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

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
