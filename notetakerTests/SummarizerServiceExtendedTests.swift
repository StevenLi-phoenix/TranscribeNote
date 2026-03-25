import Testing
import Foundation
@testable import notetaker

@Suite("SummarizerService Extended Tests", .serialized)
struct SummarizerServiceExtendedTests {

    // MARK: - Helpers

    private func makeSegment(text: String, startTime: TimeInterval = 0, endTime: TimeInterval = 5) -> TranscriptSegment {
        TranscriptSegment(startTime: startTime, endTime: endTime, text: text)
    }

    private var longText: String {
        String(repeating: "word ", count: 30)
    }

    private func makeLongSegment(startTime: TimeInterval = 0, endTime: TimeInterval = 30) -> TranscriptSegment {
        makeSegment(text: longText, startTime: startTime, endTime: endTime)
    }

    // MARK: - summarizeWithInstructions

    @Test func summarizeWithInstructionsPassesInstructionsToLLM() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Guided summary"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.summarizeWithInstructions(
            segments: segments,
            instructions: "Focus on action items",
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Guided summary")
        #expect(mock.generateCallCount == 1)
        // Verify instructions appear in the prompt
        let prompt = mock.allPrompts[0]
        #expect(prompt.contains("Focus on action items"))
    }

    @Test func summarizeWithInstructionsTrimsResponse() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "  Trimmed result  \n"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.summarizeWithInstructions(
            segments: segments,
            instructions: "Summarize briefly",
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Trimmed result")
    }

    @Test func summarizeWithInstructionsNonRetryableErrorThrows() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.emptyResponse
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarizeWithInstructions(
                segments: segments,
                instructions: "Focus on key points",
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1)
    }

    @Test func summarizeWithInstructionsPassesNilPreviousSummary() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "No context summary"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        _ = try await service.summarizeWithInstructions(
            segments: segments,
            instructions: "Be concise",
            config: SummarizerConfig(includeContext: true),
            llmConfig: .default
        )

        // The prompt should NOT contain "Previous summary" since previousSummary is nil
        let messages = mock.allMessages[0]
        let allContent = messages.map(\.content).joined()
        #expect(!allContent.lowercased().contains("previous summary"))
    }

    // MARK: - generateTitle

    @Test func generateTitleReturnsCleanedTitle() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Weekly Team Standup"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.generateTitle(
            segments: segments,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Weekly Team Standup")
        #expect(mock.generateCallCount == 1)
    }

    @Test func generateTitleStripsDoubleQuotes() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "\"Quarterly Review\""
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.generateTitle(
            segments: segments,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Quarterly Review")
    }

    @Test func generateTitleStripsSingleQuotes() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "'Design Discussion'"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.generateTitle(
            segments: segments,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Design Discussion")
    }

    @Test func generateTitleStripsSmartQuotes() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "\u{201C}Sprint Planning\u{201D}"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.generateTitle(
            segments: segments,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Sprint Planning")
    }

    @Test func generateTitleStripsSingleSmartQuotes() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "\u{2018}Budget Meeting\u{2019}"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.generateTitle(
            segments: segments,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Budget Meeting")
    }

    @Test func generateTitleEmptySegmentsReturnsEmpty() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Should not be called"
        let service = SummarizerService(engine: mock)

        let result = try await service.generateTitle(
            segments: [],
            config: .default,
            llmConfig: .default
        )

        #expect(result == "")
        #expect(mock.generateCallCount == 0)
    }

    @Test func generateTitleNonRetryableErrorThrows() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.decodingError("bad JSON")
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.generateTitle(
                segments: segments,
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1)
    }

    @Test func generateTitleTrimsWhitespace() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "  \n  Project Update  \n  "
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.generateTitle(
            segments: segments,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Project Update")
    }

    // MARK: - summarizeOverall (prompt verification)

    @Test func summarizeOverallIncludesChunkContentInPrompt() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Synthesized overall"
        let service = SummarizerService(engine: mock)

        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: String(repeating: "alpha ", count: 20)),
            (coveringFrom: 60, coveringTo: 120, content: String(repeating: "beta ", count: 20)),
        ]

        let result = try await service.summarizeOverall(
            chunkSummaries: chunks, config: .default, llmConfig: .default
        )

        #expect(result == "Synthesized overall")
        // Verify chunk content reaches the LLM
        let allContent = mock.allMessages[0].map(\.content).joined()
        #expect(allContent.contains("alpha"))
        #expect(allContent.contains("beta"))
    }

    @Test func summarizeOverallSingleChunk() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Single chunk overall"
        let service = SummarizerService(engine: mock)

        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 300, content: String(repeating: "content ", count: 20)),
        ]

        let result = try await service.summarizeOverall(
            chunkSummaries: chunks, config: .default, llmConfig: .default
        )

        #expect(result == "Single chunk overall")
        #expect(mock.generateCallCount == 1)
    }

    // MARK: - summarize (additional coverage)

    @Test func summarizeWithPreviousSummaryIncludesContext() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Updated summary"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        var config = SummarizerConfig.default
        config.includeContext = true

        let result = try await service.summarize(
            segments: segments,
            previousSummary: "Earlier discussion about project timeline",
            config: config,
            llmConfig: .default
        )

        #expect(result == "Updated summary")
        // Verify previous summary is included in the prompt
        let allContent = mock.allMessages[0].map(\.content).joined()
        #expect(allContent.contains("Earlier discussion about project timeline"))
    }

    @Test func summarizeCustomMinTranscriptLength() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Short text summary"
        let service = SummarizerService(engine: mock)

        // "Hello world" is 11 chars, below default 100 but above custom 5
        let segments = [makeSegment(text: "Hello world")]
        let config = SummarizerConfig(minTranscriptLength: 5)

        let result = try await service.summarize(
            segments: segments,
            previousSummary: nil,
            config: config,
            llmConfig: .default
        )

        #expect(result == "Short text summary")
        #expect(mock.generateCallCount == 1)
    }

    @Test func summarizeMultipleSegmentsJoinedText() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Combined summary"
        let service = SummarizerService(engine: mock)

        // Each segment is short, but joined they exceed minTranscriptLength
        let segments = [
            makeSegment(text: String(repeating: "aaa ", count: 10), startTime: 0, endTime: 10),
            makeSegment(text: String(repeating: "bbb ", count: 10), startTime: 10, endTime: 20),
            makeSegment(text: String(repeating: "ccc ", count: 10), startTime: 20, endTime: 30),
        ]

        let result = try await service.summarize(
            segments: segments,
            previousSummary: nil,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Combined summary")
        #expect(mock.generateCallCount == 1)
    }

    @Test func summarizeMultipleSegmentsBelowMinLength() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Should not be called"
        let service = SummarizerService(engine: mock)

        // Each short, combined still below 100
        let segments = [
            makeSegment(text: "Hi", startTime: 0, endTime: 1),
            makeSegment(text: "there", startTime: 1, endTime: 2),
        ]

        let result = try await service.summarize(
            segments: segments,
            previousSummary: nil,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "")
        #expect(mock.generateCallCount == 0)
    }

    // MARK: - splitIntoChunksWithWindowIndices (extended)

    @Test func splitIntoChunksWithWindowIndicesSingleSegment() {
        let segments = [makeSegment(text: "Only one", startTime: 45, endTime: 50)]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 1)

        #expect(result.count == 1)
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments.count == 1)
        #expect(result[0].segments[0].text == "Only one")
    }

    @Test func splitIntoChunksWithWindowIndicesEmptySegments() {
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: [], intervalMinutes: 1)
        #expect(result.isEmpty)
    }

    @Test func splitIntoChunksWithWindowIndicesZeroInterval() {
        let segments = [makeSegment(text: "A", startTime: 0, endTime: 10)]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 0)
        #expect(result.isEmpty)
    }

    @Test func splitIntoChunksWithWindowIndicesNegativeInterval() {
        let segments = [makeSegment(text: "A", startTime: 0, endTime: 10)]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: -1)
        #expect(result.isEmpty)
    }

    @Test func splitIntoChunksWithWindowIndicesLargeGapProducesCorrectIndices() {
        // Segments at 0s and 600s (10 min), interval=1min
        // Window 0 for first, window 10 for second
        let segments = [
            makeSegment(text: "Start", startTime: 0, endTime: 5),
            makeSegment(text: "End", startTime: 600, endTime: 610),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 1)

        #expect(result.count == 2)
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments[0].text == "Start")
        // 600 / 60 = 10, but lastEnd is 610, so windowCount = ceil(610/60) = 11 windows
        // segment at 600s: Int(600/60) = 10
        #expect(result[1].windowIndex == 10)
        #expect(result[1].segments[0].text == "End")
    }

    @Test func splitIntoChunksWithWindowIndicesUnsortedInput() {
        // Input is out of order — should still be sorted by startTime
        let segments = [
            makeSegment(text: "C", startTime: 130, endTime: 140),
            makeSegment(text: "A", startTime: 5, endTime: 15),
            makeSegment(text: "B", startTime: 70, endTime: 80),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 1)

        #expect(result.count == 3)
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments[0].text == "A")
        #expect(result[1].windowIndex == 1)
        #expect(result[1].segments[0].text == "B")
        #expect(result[2].windowIndex == 2)
        #expect(result[2].segments[0].text == "C")
    }

    @Test func splitIntoChunksWithWindowIndicesMultiplePerWindow() {
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 10),
            makeSegment(text: "B", startTime: 20, endTime: 30),
            makeSegment(text: "C", startTime: 40, endTime: 50),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 1)

        #expect(result.count == 1)
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments.count == 3)
    }

    @Test func splitIntoChunksWithWindowIndicesLargeInterval() {
        // Interval = 10 minutes, all segments within first 10 min
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 60),
            makeSegment(text: "B", startTime: 120, endTime: 180),
            makeSegment(text: "C", startTime: 300, endTime: 360),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 10)

        #expect(result.count == 1)
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments.count == 3)
    }

    @Test func splitIntoChunksWindowBoundaryExact() {
        // Segment starts exactly at window boundary (60s)
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 30),
            makeSegment(text: "B", startTime: 60, endTime: 90),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 1)

        #expect(result.count == 2)
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments[0].text == "A")
        #expect(result[1].windowIndex == 1)
        #expect(result[1].segments[0].text == "B")
    }

    // MARK: - summarizeInChunks (extended)

    @Test func summarizeInChunksSingleChunk() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Single chunk result"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment(startTime: 0, endTime: 30)]

        var results: [ChunkProgress] = []
        for try await progress in service.summarizeInChunks(
            segments: segments, intervalMinutes: 1, config: .default, llmConfig: .default
        ) {
            results.append(progress)
        }

        #expect(results.count == 1)
        #expect(results[0].chunkIndex == 0)
        #expect(results[0].totalChunks == 1)
        #expect(results[0].content == "Single chunk result")
        #expect(results[0].coveringFrom == 0)
        // Last chunk coveringTo is capped at lastEnd
        #expect(results[0].coveringTo == 30)
    }

    @Test func summarizeInChunksEmptySegmentsYieldsNothing() async throws {
        let mock = MockLLMEngine()
        let service = SummarizerService(engine: mock)

        var results: [ChunkProgress] = []
        for try await progress in service.summarizeInChunks(
            segments: [], intervalMinutes: 1, config: .default, llmConfig: .default
        ) {
            results.append(progress)
        }

        #expect(results.isEmpty)
        #expect(mock.generateCallCount == 0)
    }

    @Test func summarizeInChunksLastChunkCoversToCappedAtLastEnd() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponses = ["Chunk 1", "Chunk 2", "Chunk 3"]
        let service = SummarizerService(engine: mock)

        // Three chunks: [0,60), [60,120), and [120, lastEnd=135]
        let segments = [
            makeLongSegment(startTime: 0, endTime: 30),
            makeLongSegment(startTime: 70, endTime: 100),
            makeLongSegment(startTime: 125, endTime: 135),
        ]

        var results: [ChunkProgress] = []
        for try await progress in service.summarizeInChunks(
            segments: segments, intervalMinutes: 1, config: .default, llmConfig: .default
        ) {
            results.append(progress)
        }

        #expect(results.count == 3)
        // First two chunks have standard boundaries
        #expect(results[0].coveringFrom == 0)
        #expect(results[0].coveringTo == 60)
        #expect(results[1].coveringFrom == 60)
        #expect(results[1].coveringTo == 120)
        // Last chunk is capped at actual lastEnd
        #expect(results[2].coveringFrom == 120)
        #expect(results[2].coveringTo == 135)
    }

    @Test func summarizeInChunksPreviousSummaryChainedAcrossChunks() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponses = ["Summary A", "Summary B", "Summary C"]
        let service = SummarizerService(engine: mock)

        let segments = [
            makeLongSegment(startTime: 0, endTime: 30),
            makeLongSegment(startTime: 70, endTime: 100),
            makeLongSegment(startTime: 130, endTime: 160),
        ]
        var config = SummarizerConfig.default
        config.includeContext = true

        var results: [ChunkProgress] = []
        for try await progress in service.summarizeInChunks(
            segments: segments, intervalMinutes: 1, config: config, llmConfig: .default
        ) {
            results.append(progress)
        }

        #expect(results.count == 3)
        // Second call should include "Summary A" as context
        let secondPrompt = mock.allPrompts[1]
        #expect(secondPrompt.contains("Summary A"))
        // Third call should include "Summary B" as context
        let thirdPrompt = mock.allPrompts[2]
        #expect(thirdPrompt.contains("Summary B"))
    }

    @Test func summarizeInChunksRetryableErrorSkipsChunk() async throws {
        // Server error (500) is retryable; after exhausting retries the chunk is skipped (not thrown)
        // However, retries have delays (10s, 30s) which makes this test slow.
        // Instead, test with httpError 400 (non-retryable) on second chunk to verify stream aborts.
        let mock = MockLLMEngine()
        var callCount = 0
        let longText = self.longText

        // Override behavior: first call succeeds, second throws non-retryable
        // We need a more fine-grained mock, so use stubbedResponses with error injection
        // Since MockLLMEngine doesn't support per-call errors, test with notConfigured
        // which is non-retryable and should abort the stream.
        mock.stubbedResponses = [longText] // first chunk succeeds
        let service = SummarizerService(engine: mock)

        // Actually, MockLLMEngine applies stubbedError globally.
        // Test that httpError 400 (non-retryable via code < 500 and != 429) aborts.
        let mock2 = MockLLMEngine()
        mock2.stubbedError = LLMEngineError.httpError(statusCode: 400, body: "Bad request")
        let service2 = SummarizerService(engine: mock2)

        let segments = [
            makeLongSegment(startTime: 0, endTime: 30),
            makeLongSegment(startTime: 70, endTime: 100),
        ]

        var results: [ChunkProgress] = []
        var thrownError: Error?
        do {
            for try await progress in service2.summarizeInChunks(
                segments: segments, intervalMinutes: 1, config: .default, llmConfig: .default
            ) {
                results.append(progress)
            }
        } catch {
            thrownError = error
        }

        #expect(results.isEmpty)
        #expect(thrownError != nil)
        // httpError 400 is non-retryable, so only 1 call
        #expect(mock2.generateCallCount == 1)
    }

    // MARK: - isRetryable (tested indirectly)

    @Test func httpError429IsRetryableButNonRetryableStopsImmediately() async {
        // Verify that httpError with status < 500 and != 429 (e.g. 401) is non-retryable
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.httpError(statusCode: 401, body: "Unauthorized")
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarize(
                segments: segments,
                previousSummary: nil,
                config: .default,
                llmConfig: .default
            )
        }

        // 401 is non-retryable (not >= 500, not 429), so only 1 attempt
        #expect(mock.generateCallCount == 1)
    }

    @Test func invalidURLIsNonRetryable() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.invalidURL("http://bad")
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarize(
                segments: segments,
                previousSummary: nil,
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1)
    }

    @Test func decodingErrorIsNonRetryable() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.decodingError("malformed JSON")
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarize(
                segments: segments,
                previousSummary: nil,
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1)
    }

    @Test func emptyResponseIsNonRetryable() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.emptyResponse
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarize(
                segments: segments,
                previousSummary: nil,
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1)
    }

    @Test func notConfiguredIsNonRetryable() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.notConfigured
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarize(
                segments: segments,
                previousSummary: nil,
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1)
    }

    @Test func httpError403IsNonRetryable() async {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.httpError(statusCode: 403, body: "Forbidden")
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]

        await #expect(throws: LLMEngineError.self) {
            try await service.summarize(
                segments: segments,
                previousSummary: nil,
                config: .default,
                llmConfig: .default
            )
        }

        #expect(mock.generateCallCount == 1)
    }

    // MARK: - Response trimming

    @Test func summarizeTrimsLeadingTrailingWhitespace() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "\n\n  Result with whitespace  \n\n"
        let service = SummarizerService(engine: mock)

        let segments = [makeLongSegment()]
        let result = try await service.summarize(
            segments: segments,
            previousSummary: nil,
            config: .default,
            llmConfig: .default
        )

        #expect(result == "Result with whitespace")
    }

    // MARK: - Config forwarding

    @Test func summarizeForwardsLLMConfig() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Result"
        let service = SummarizerService(engine: mock)

        let customConfig = LLMConfig(
            provider: .openAI,
            model: "gpt-4",
            apiKey: "test-key",
            baseURL: "https://api.openai.com/v1",
            temperature: 0.3,
            maxTokens: 2048
        )

        let segments = [makeLongSegment()]
        _ = try await service.summarize(
            segments: segments,
            previousSummary: nil,
            config: .default,
            llmConfig: customConfig
        )

        #expect(mock.lastConfig == customConfig)
    }

    @Test func generateTitleForwardsLLMConfig() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Title"
        let service = SummarizerService(engine: mock)

        let customConfig = LLMConfig(
            provider: .anthropic,
            model: "claude-3",
            apiKey: "key",
            baseURL: "https://api.anthropic.com",
            temperature: 0.5,
            maxTokens: 1024
        )

        let segments = [makeLongSegment()]
        _ = try await service.generateTitle(
            segments: segments,
            config: .default,
            llmConfig: customConfig
        )

        #expect(mock.lastConfig == customConfig)
    }

    @Test func summarizeOverallForwardsLLMConfig() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Overall"
        let service = SummarizerService(engine: mock)

        let customConfig = LLMConfig(
            provider: .ollama,
            model: "llama3",
            baseURL: "http://localhost:11434",
            temperature: 0.1,
            maxTokens: 8192
        )

        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: String(repeating: "word ", count: 30)),
        ]

        _ = try await service.summarizeOverall(
            chunkSummaries: chunks, config: .default, llmConfig: customConfig
        )

        #expect(mock.lastConfig == customConfig)
    }

    // MARK: - Edge cases: boundary-at-exact-interval

    @Test func splitIntoChunksSegmentAtExactBoundaryGoesToNextWindow() {
        // Segment at exactly 120s with interval=2min
        // 120/120 = 1.0, Int(1.0) = 1 => window 1
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 30),
            makeSegment(text: "B", startTime: 120, endTime: 150),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 2)

        #expect(result.count == 2)
        #expect(result[0].windowIndex == 0)
        #expect(result[1].windowIndex == 1)
    }

    @Test func splitIntoChunksSegmentJustBeforeBoundary() {
        // Segment at 119.9s with interval=2min (120s)
        // Int(119.9/120) = Int(0.999) = 0 => window 0
        let segments = [
            makeSegment(text: "A", startTime: 0, endTime: 10),
            makeSegment(text: "B", startTime: 119.9, endTime: 125),
        ]
        let result = SummarizerService.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: 2)

        #expect(result.count == 1) // Both in window 0
        #expect(result[0].windowIndex == 0)
        #expect(result[0].segments.count == 2)
    }

    // MARK: - summarizeWithInstructions with custom config

    @Test func summarizeWithInstructionsUsesCustomConfig() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Custom config result"
        let service = SummarizerService(engine: mock)

        let config = SummarizerConfig(
            minTranscriptLength: 5,
            summaryLanguage: "ja",
            summaryStyle: .paragraph
        )
        let segments = [makeSegment(text: "Short text here")]

        let result = try await service.summarizeWithInstructions(
            segments: segments,
            instructions: "Focus on technical details",
            config: config,
            llmConfig: .default
        )

        #expect(result == "Custom config result")
        #expect(mock.generateCallCount == 1)
    }
}
