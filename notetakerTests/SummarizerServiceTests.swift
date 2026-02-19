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

    // MARK: - splitIntoChunks

    @Test func splitIntoChunksBasic() {
        // 3 segments spanning ~5 minutes, interval=2min — each in separate windows
        let segments = [
            makeSegment(text: "A", startTime: 10, endTime: 30),
            makeSegment(text: "B", startTime: 130, endTime: 150),
            makeSegment(text: "C", startTime: 250, endTime: 270),
        ]
        let chunks = SummarizerService.splitIntoChunks(segments: segments, intervalMinutes: 2)
        #expect(chunks.count == 3)
        #expect(chunks[0][0].text == "A")
        #expect(chunks[1][0].text == "B")
        #expect(chunks[2][0].text == "C")
    }

    @Test func splitIntoChunksMultipleSegmentsPerChunk() {
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 10),
            makeSegment(text: "B", startTime: 15, endTime: 25),
            makeSegment(text: "C", startTime: 40, endTime: 50),
            makeSegment(text: "D", startTime: 70, endTime: 80),
        ]
        let chunks = SummarizerService.splitIntoChunks(segments: segments, intervalMinutes: 1)
        #expect(chunks.count == 2)
        #expect(chunks[0].count == 3) // A, B, C all in [0, 60)
        #expect(chunks[1].count == 1) // D in [60, ...)
    }

    @Test func splitIntoChunksEmpty() {
        let chunks = SummarizerService.splitIntoChunks(segments: [], intervalMinutes: 1)
        #expect(chunks.isEmpty)
    }

    @Test func splitIntoChunksAllInOneWindow() {
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 10),
            makeSegment(text: "B", startTime: 20, endTime: 30),
        ]
        let chunks = SummarizerService.splitIntoChunks(segments: segments, intervalMinutes: 5)
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 2)
    }

    @Test func splitIntoChunksSkipsEmptyWindows() {
        // Gap between 0s and 300s — intermediate windows should be filtered
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 10),
            makeSegment(text: "B", startTime: 300, endTime: 310),
        ]
        let chunks = SummarizerService.splitIntoChunks(segments: segments, intervalMinutes: 1)
        #expect(chunks.count == 2)
        #expect(chunks[0][0].text == "A")
        #expect(chunks[1][0].text == "B")
    }

    @Test func splitIntoChunksZeroInterval() {
        let segments = [makeSegment(text: "A", startTime: 0, endTime: 10)]
        let chunks = SummarizerService.splitIntoChunks(segments: segments, intervalMinutes: 0)
        #expect(chunks.isEmpty)
    }

    // MARK: - summarizeInChunks

    @Test func summarizeInChunksYieldsProgressPerChunk() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponses = ["Notes for chunk 1", "Notes for chunk 2"]
        let service = SummarizerService(engine: mock)

        let longText = String(repeating: "word ", count: 30)
        let segments = [
            makeSegment(text: longText, startTime: 0, endTime: 30),
            makeSegment(text: longText, startTime: 70, endTime: 100),
        ]

        var progresses: [ChunkProgress] = []
        for try await progress in service.summarizeInChunks(
            segments: segments, intervalMinutes: 1, config: .default, llmConfig: .default
        ) {
            progresses.append(progress)
        }

        #expect(progresses.count == 2)
        #expect(progresses[0].chunkIndex == 0)
        #expect(progresses[0].totalChunks == 2)
        #expect(progresses[0].content == "Notes for chunk 1")
        // Window boundaries: chunk 0 = [0, 60), chunk 1 = last window capped at lastEnd
        #expect(progresses[0].coveringFrom == 0)
        #expect(progresses[0].coveringTo == 60)
        #expect(progresses[1].chunkIndex == 1)
        #expect(progresses[1].content == "Notes for chunk 2")
        #expect(progresses[1].coveringFrom == 60)
        #expect(progresses[1].coveringTo == 100) // Last window capped at actual last segment endTime
        #expect(mock.generateCallCount == 2)
    }

    @Test func summarizeInChunksPassesPreviousContext() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponses = ["First chunk notes", "Second chunk notes"]
        let service = SummarizerService(engine: mock)

        let longText = String(repeating: "word ", count: 30)
        let segments = [
            makeSegment(text: longText, startTime: 0, endTime: 30),
            makeSegment(text: longText, startTime: 70, endTime: 100),
        ]
        var config = SummarizerConfig.default
        config.includeContext = true

        var results: [ChunkProgress] = []
        for try await progress in service.summarizeInChunks(
            segments: segments, intervalMinutes: 1, config: config, llmConfig: .default
        ) {
            results.append(progress)
        }

        #expect(results.count == 2)
        // Second prompt must include first chunk's output as context
        let secondPrompt = mock.allPrompts[1]
        #expect(secondPrompt.contains("First chunk notes"))
    }

    @Test func summarizeInChunksSkipsShortChunks() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Notes"
        let service = SummarizerService(engine: mock)

        let segments = [
            makeSegment(text: String(repeating: "word ", count: 30), startTime: 0, endTime: 30),
            makeSegment(text: "Short", startTime: 70, endTime: 75),
        ]

        var results: [ChunkProgress] = []
        for try await progress in service.summarizeInChunks(
            segments: segments, intervalMinutes: 1, config: .default, llmConfig: .default
        ) {
            results.append(progress)
        }

        // Only chunk 0 yields (chunk 1 has "Short" which is below minTranscriptLength)
        #expect(results.count == 1)
        #expect(results[0].chunkIndex == 0)
    }

    @Test func summarizeInChunksThrowsOnNonRetryableError() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.notConfigured
        let service = SummarizerService(engine: mock)

        let segments = [makeSegment(text: String(repeating: "word ", count: 30), startTime: 0, endTime: 30)]

        await #expect(throws: LLMEngineError.self) {
            for try await _ in service.summarizeInChunks(
                segments: segments, intervalMinutes: 1, config: .default, llmConfig: .default
            ) {}
        }
    }

    @Test func summarizeInChunksNonRetryableErrorAbortsRemainingChunks() async {
        // A non-retryable error on the first chunk terminates the stream immediately
        // — no further chunks are attempted.
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.invalidURL("bad")
        let service = SummarizerService(engine: mock)

        let longText = String(repeating: "word ", count: 30)
        let segments = [
            makeSegment(text: longText, startTime: 0, endTime: 30),
            makeSegment(text: longText, startTime: 70, endTime: 100),
        ]

        var results: [ChunkProgress] = []
        var thrownError: Error?
        do {
            for try await progress in service.summarizeInChunks(
                segments: segments, intervalMinutes: 1, config: .default, llmConfig: .default
            ) {
                results.append(progress)
            }
        } catch {
            thrownError = error
        }

        // Stream threw, no chunks succeeded, engine called exactly once (no retry for invalidURL)
        #expect(results.isEmpty)
        #expect(thrownError != nil)
        #expect(mock.generateCallCount == 1)
    }

    // MARK: - Zero-based window tests

    @Test func splitIntoChunksZeroBasedWindows() {
        // First segment starts at 9s. With interval=1min, window 0 = [0, 60).
        // Segments at 9s and 50s both in window 0, segment at 70s in window 1.
        let segments = [
            makeSegment(text: "A", startTime: 9, endTime: 20),
            makeSegment(text: "B", startTime: 50, endTime: 55),
            makeSegment(text: "C", startTime: 70, endTime: 80),
        ]
        let chunks = SummarizerService.splitIntoChunks(segments: segments, intervalMinutes: 1)
        #expect(chunks.count == 2)
        #expect(chunks[0].count == 2) // A and B in window [0, 60)
        #expect(chunks[0][0].text == "A")
        #expect(chunks[0][1].text == "B")
        #expect(chunks[1].count == 1) // C in window [60, 120)
        #expect(chunks[1][0].text == "C")
    }

    @Test func splitIntoChunksWithWindowIndicesReturnsCorrectBoundaries() {
        // Segments at 0s, 65s, 310s with interval=1min
        // → windowIndex 0 (0s), 1 (65s), 5 (310s)
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 10),
            makeSegment(text: "B", startTime: 65, endTime: 75),
            makeSegment(text: "C", startTime: 310, endTime: 320),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 1)
        #expect(result.count == 3)
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments[0].text == "A")
        #expect(result[1].windowIndex == 1)
        #expect(result[1].segments[0].text == "B")
        #expect(result[2].windowIndex == 5)
        #expect(result[2].segments[0].text == "C")
    }

    // MARK: - summarizeOverall

    @Test func summarizeOverallSuccess() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "  Overall summary  "
        let service = SummarizerService(engine: mock)

        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: String(repeating: "word ", count: 30)),
            (coveringFrom: 60, coveringTo: 120, content: String(repeating: "more ", count: 30)),
        ]

        let result = try await service.summarizeOverall(
            chunkSummaries: chunks, config: .default, llmConfig: .default
        )

        #expect(result == "Overall summary")
        #expect(mock.generateCallCount == 1)
    }

    @Test func summarizeOverallEmptyChunks() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Should not be called"
        let service = SummarizerService(engine: mock)

        let result = try await service.summarizeOverall(
            chunkSummaries: [], config: .default, llmConfig: .default
        )

        #expect(result == "")
        #expect(mock.generateCallCount == 0)
    }

    @Test func summarizeOverallTooShort() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Should not be called"
        let service = SummarizerService(engine: mock)

        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Short"),
        ]

        let result = try await service.summarizeOverall(
            chunkSummaries: chunks, config: .default, llmConfig: .default
        )

        #expect(result == "")
        #expect(mock.generateCallCount == 0)
    }

    @Test func summarizeOverallNonRetryableThrows() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.notConfigured
        let service = SummarizerService(engine: mock)

        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: String(repeating: "word ", count: 30)),
        ]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarizeOverall(
                chunkSummaries: chunks, config: .default, llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1) // No retry for non-retryable error
    }
}
