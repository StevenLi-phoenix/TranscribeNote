import Testing
import Foundation
@testable import notetaker

@Suite struct ChatServiceTests {
    private func makeSegments(_ texts: [(TimeInterval, String)]) -> [TranscriptSegment] {
        texts.map { TranscriptSegment(startTime: $0.0, endTime: $0.0 + 5, text: $0.1) }
    }

    @Test func sendMessageReturnsAssistantResponse() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "The meeting discussed budgets."
        let service = ChatService(engine: mock)
        let segments = makeSegments([(0, "We need to discuss the budget")])

        let response = try await service.sendMessage("What was discussed?", segments: segments, llmConfig: .default)

        #expect(response.role == .assistant)
        #expect(response.content == "The meeting discussed budgets.")
        #expect(mock.generateCallCount == 1)
    }

    @Test func sendMessageAppendsToHistory() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "Answer 1"
        let service = ChatService(engine: mock)
        let segments = makeSegments([(0, "Hello")])

        _ = try await service.sendMessage("Question 1", segments: segments, llmConfig: .default)

        let history = service.conversationHistory
        #expect(history.count == 2)
        #expect(history[0].role == .user)
        #expect(history[0].content == "Question 1")
        #expect(history[1].role == .assistant)
        #expect(history[1].content == "Answer 1")
    }

    @Test func buildMessagesIncludesSystemPromptWithTranscript() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "OK"
        let service = ChatService(engine: mock)
        let segments = makeSegments([(65, "One minute mark")])

        _ = try await service.sendMessage("test", segments: segments, llmConfig: .default)

        let messages = mock.lastMessages!
        // First message is system
        #expect(messages[0].role == .system)
        #expect(messages[0].content.contains("[01:05] One minute mark"))
        #expect(messages[0].content.contains("Use ONLY information from the transcript"))
    }

    @Test func buildMessagesIncludesConversationHistory() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponses = ["First answer", "Second answer"]
        let service = ChatService(engine: mock)
        let segments = makeSegments([(0, "Hello")])

        _ = try await service.sendMessage("Q1", segments: segments, llmConfig: .default)
        _ = try await service.sendMessage("Q2", segments: segments, llmConfig: .default)

        // Second call should include history: system + Q1 + A1 + Q2
        let messages = mock.allMessages[1]
        #expect(messages.count == 4)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
        #expect(messages[1].content == "Q1")
        #expect(messages[2].role == .assistant)
        #expect(messages[2].content == "First answer")
        #expect(messages[3].role == .user)
        #expect(messages[3].content == "Q2")
    }

    @Test func systemPromptHasCacheHint() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "OK"
        let service = ChatService(engine: mock)
        let segments = makeSegments([(0, "Hello")])

        _ = try await service.sendMessage("test", segments: segments, llmConfig: .default)

        let systemMessage = mock.lastMessages![0]
        #expect(systemMessage.cacheHint == true)
    }

    @Test func formatTranscriptShortPassthrough() {
        let segments = makeSegments([(0, "Hello"), (5, "World")])
        let result = ChatService.formatTranscript(segments: segments)

        #expect(result.contains("[00:00] Hello"))
        #expect(result.contains("[00:05] World"))
        #expect(!result.contains("omitted"))
    }

    @Test func formatTranscriptLongTruncates() {
        // Create segments that exceed the limit
        let longText = String(repeating: "word ", count: 200)
        var segments: [TranscriptSegment] = []
        for i in 0..<100 {
            segments.append(TranscriptSegment(startTime: Double(i * 10), endTime: Double(i * 10 + 5), text: longText))
        }

        let result = ChatService.formatTranscript(segments: segments, maxCharacters: 1000)
        #expect(result.contains("omitted"))
        #expect(result.count < 1500) // Some overhead for the omission marker
    }

    @Test func formatTranscriptPreservesStartAndEnd() {
        let longText = String(repeating: "x", count: 500)
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 5, text: "START_MARKER"),
            TranscriptSegment(startTime: 10, endTime: 15, text: longText),
            TranscriptSegment(startTime: 20, endTime: 25, text: longText),
            TranscriptSegment(startTime: 30, endTime: 35, text: "END_MARKER"),
        ]

        let result = ChatService.formatTranscript(segments: segments, maxCharacters: 200)
        #expect(result.contains("START_MARKER"))
        #expect(result.contains("END_MARKER"))
    }

    @Test func clearHistoryResetsMessages() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "OK"
        let service = ChatService(engine: mock)
        let segments = makeSegments([(0, "Hello")])

        _ = try await service.sendMessage("Q1", segments: segments, llmConfig: .default)
        #expect(service.conversationHistory.count == 2)

        service.clearHistory()
        #expect(service.conversationHistory.isEmpty)
    }

    @Test func emptySegmentsHandledGracefully() async throws {
        let mock = MockLLMEngine()
        mock.stubbedResponse = "No transcript available."
        let service = ChatService(engine: mock)

        let response = try await service.sendMessage("What happened?", segments: [], llmConfig: .default)

        #expect(response.content == "No transcript available.")
        // System prompt should still be present but without transcript content
        let systemMsg = mock.lastMessages![0]
        #expect(!systemMsg.content.contains("<transcript>"))
    }

    @Test func engineErrorPropagates() async throws {
        let mock = MockLLMEngine()
        mock.stubbedError = LLMEngineError.notConfigured
        let service = ChatService(engine: mock)
        let segments = makeSegments([(0, "Hello")])

        await #expect(throws: LLMEngineError.self) {
            try await service.sendMessage("test", segments: segments, llmConfig: .default)
        }

        // User message should still be in history (was added before generate)
        #expect(service.conversationHistory.count == 1)
        #expect(service.conversationHistory[0].role == .user)
    }

    @Test func conversationWindowTrimsOldMessages() {
        var messages: [ChatMessage] = []
        // Create 15 pairs (30 messages) — should trim to 10 pairs (20 messages)
        for i in 0..<15 {
            messages.append(ChatMessage(role: .user, content: "Q\(i)"))
            messages.append(ChatMessage(role: .assistant, content: "A\(i)"))
        }

        let trimmed = ChatService.trimConversation(messages)
        #expect(trimmed.count == 20)
        // Should keep the last 10 pairs (Q5..Q14, A5..A14)
        #expect(trimmed[0].content == "Q5")
        #expect(trimmed[1].content == "A5")
        #expect(trimmed[trimmed.count - 1].content == "A14")
    }

    @Test func transcriptFormattedAsMMSS() {
        let segments = makeSegments([(0, "Start"), (90, "Ninety seconds")])
        let result = ChatService.formatTranscript(segments: segments)

        #expect(result.contains("[00:00] Start"))
        #expect(result.contains("[01:30] Ninety seconds"))
    }
}
