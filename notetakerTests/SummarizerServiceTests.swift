import Testing
import Foundation
@testable import notetaker

struct SummarizerServiceTests {
    private func makeSegment(text: String, startTime: TimeInterval = 0, endTime: TimeInterval = 5) -> TranscriptSegment {
        TranscriptSegment(startTime: startTime, endTime: endTime, text: text)
    }

    @Test func successfulSummarization() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "  Summary result  "
        let service = SummarizerService(engine: mock)

        let segments = [makeSegment(text: String(repeating: "word ", count: 30))]
        let result = try await service.summarize(
            segments: segments,
            previousSummary: nil,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Summary result")
        #expect(mock.generateCallCount == 1)
    }

    @Test func minTranscriptLengthGuard() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Should not be called"
        let service = SummarizerService(engine: mock)

        let segments = [makeSegment(text: "Short")]
        let result = try await service.summarize(
            segments: segments,
            previousSummary: nil,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "")
        #expect(mock.generateCallCount == 0)
    }

    @Test func emptySegmentsReturnsEmpty() async throws {
        let mock = MockLLMEngine()
        let service = SummarizerService(engine: mock)

        let result = try await service.summarize(
            segments: [],
            previousSummary: nil,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "")
        #expect(mock.generateCallCount == 0)
    }

    @Test func nonRetryableErrorThrowsImmediately() async throws {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.invalidURL("bad")
        let service = SummarizerService(engine: mock)

        let segments = [makeSegment(text: String(repeating: "word ", count: 30))]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarize(
                segments: segments,
                previousSummary: nil,
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1) // No retry
    }
}
