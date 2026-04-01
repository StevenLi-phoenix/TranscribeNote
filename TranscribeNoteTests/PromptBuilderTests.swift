import Testing
import Foundation
@testable import TranscribeNote

struct PromptBuilderTests {
    private func makeSegment(startTime: TimeInterval, endTime: TimeInterval, text: String) -> TranscriptSegment {
        TranscriptSegment(startTime: startTime, endTime: endTime, text: text)
    }

    /// Concatenate all message content for text assertions.
    private func fullText(_ messages: [LLMMessage]) -> String {
        messages.map(\.content).joined(separator: "\n\n")
    }

    /// Get just the system message content.
    private func systemContent(_ messages: [LLMMessage]) -> String {
        messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
    }

    /// Get just the user message content.
    private func userContent(_ messages: [LLMMessage]) -> String {
        messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")
    }

    // MARK: - Message structure

    @Test func returnsSystemAndUserMessages() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)

        let systemMsgs = messages.filter { $0.role == .system }
        let userMsgs = messages.filter { $0.role == .user }
        #expect(systemMsgs.count == 1)
        #expect(userMsgs.count >= 1)
    }

    @Test func systemMessageHasCacheHint() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)

        let systemMsg = messages.first { $0.role == .system }!
        #expect(systemMsg.cacheHint == true)
    }

    @Test func transcriptMessageHasNoCacheHint() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)

        let lastUserMsg = messages.last { $0.role == .user }!
        #expect(lastUserMsg.cacheHint == false)
    }

    // MARK: - Style tests

    @Test func bulletsStyleContainsBulletPoints() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .bullets

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(fullText(messages).contains("bullet points"))
    }

    @Test func paragraphStyleContainsParagraph() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .paragraph

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(fullText(messages).contains("paragraph"))
    }

    @Test func actionItemsStyleContainsChecklist() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .actionItems

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let text = fullText(messages)
        #expect(text.contains("checklist") || text.contains("action items"))
    }

    @Test func includesPreviousSummary() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Previous notes here", config: config)
        #expect(fullText(messages).contains("Previous notes here"))
    }

    @Test func previousSummaryHasCacheHint() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Previous notes here", config: config)
        let contextMsg = messages.first { $0.role == .user && $0.content.contains("Previous notes here") }
        #expect(contextMsg?.cacheHint == true)
    }

    @Test func excludesPreviousSummaryWhenDisabled() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = false

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Previous notes here", config: config)
        #expect(!fullText(messages).contains("Previous notes here"))
    }

    @Test func languageInstructionWhenNotAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Japanese"

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(fullText(messages).contains("Japanese"))
    }

    @Test func noLanguageInstructionWhenAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(!fullText(messages).contains("Respond in"))
    }

    @Test func segmentsFormattedWithTimestamps() {
        let segments = [
            makeSegment(startTime: 65, endTime: 70, text: "First segment"),
            makeSegment(startTime: 130, endTime: 135, text: "Second segment"),
        ]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let text = fullText(messages)
        #expect(text.contains("[01:05] First segment"))
        #expect(text.contains("[02:10] Second segment"))
    }

    @Test func emptySegmentsDoesNotCrash() {
        let config = SummarizerConfig.default
        let messages = PromptBuilder.buildSummarizationPrompt(segments: [], previousSummary: nil, config: config)
        #expect(!messages.isEmpty) // At least system message
        // System message mentions <transcript> tags in instructions, but no actual transcript block
        let userMessages = messages.filter { $0.role == .user }
        let userText = userMessages.map(\.content).joined()
        #expect(!userText.contains("<transcript>"))
    }

    @Test func lectureNotesStyleContainsDetailedInstructions() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let text = fullText(messages)
        #expect(text.contains("lecture note-taker"))
        #expect(text.contains("**Topic:**"))
    }

    @Test func lectureNotesUsesNotesContextLabel() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Prior notes", config: config)
        let text = fullText(messages)
        #expect(text.contains("Previous notes for context:"))
        #expect(text.contains("Prior notes"))
    }

    @Test func bulletsStyleUsesSummaryContextLabel() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryStyle = .bullets
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Previous data", config: config)
        #expect(fullText(messages).contains("Previous summary for context:"))
    }

    // MARK: - additionalInstructions

    @Test func additionalInstructionsAppearInPrompt() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "Focus on action items"
        )
        let text = fullText(messages)
        #expect(text.contains("Additional user instructions:"))
        #expect(text.contains("Focus on action items"))
    }

    @Test func additionalInstructionsOmittedWhenNil() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: nil
        )
        #expect(!fullText(messages).contains("Additional user instructions"))
    }

    @Test func additionalInstructionsOmittedWhenEmpty() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: ""
        )
        #expect(!fullText(messages).contains("Additional user instructions"))
    }

    @Test func additionalInstructionsSanitized() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "Line1\nLine2\rLine3"
        )
        let text = fullText(messages)
        // Newlines should be replaced with spaces
        #expect(!text.contains("Line1\n"))
        #expect(text.contains("Line1 Line2 Line3"))
    }

    @Test func additionalInstructionsTruncatedAt500Chars() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default
        let longInstructions = String(repeating: "x", count: 600)

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: longInstructions
        )
        // Additional instructions are in a user message (not system) to reduce prompt injection risk
        let instructionsMsg = messages.first { $0.role == .user && $0.content.contains("Additional user instructions") }!
        let xCount = instructionsMsg.content.filter { $0 == "x" }.count
        #expect(xCount == 500)
    }

    @Test func additionalInstructionsNotInSystemMessage() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "Focus on action items"
        )
        // Additional instructions must NOT appear in the system message
        let sysText = systemContent(messages)
        #expect(!sysText.contains("Additional user instructions"))
        #expect(!sysText.contains("Focus on action items"))
        // They should be in a user message instead
        let instructionsMsg = messages.first { $0.role == .user && $0.content.contains("Additional user instructions") }
        #expect(instructionsMsg != nil)
        #expect(instructionsMsg?.content.contains("Focus on action items") == true)
    }

    // MARK: - buildOverallSummaryPrompt

    @Test func overallPromptContainsSynthesizeInstruction() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "First section summary"),
            (coveringFrom: 60, coveringTo: 120, content: "Second section summary"),
        ]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let text = fullText(messages)
        #expect(text.contains("Synthesize"))
        #expect(text.contains("First section summary"))
        #expect(text.contains("Second section summary"))
        #expect(text.contains("[00:00 – 01:00]"))
        #expect(text.contains("[01:00 – 02:00]"))
    }

    @Test func overallPromptRespectsLanguage() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Some summary"),
        ]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Japanese"

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        #expect(fullText(messages).contains("Japanese"))
    }

    @Test func overallPromptLectureNotesStyle() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Lecture chunk"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let text = fullText(messages)
        #expect(text.contains("lecture note-taker"))
        #expect(text.contains("**Topic:**"))
        #expect(text.contains("Synthesize"))
    }

    @Test func overallPromptSystemHasCacheHint() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Summary"),
        ]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let systemMsg = messages.first { $0.role == .system }!
        #expect(systemMsg.cacheHint == true)
    }

    // MARK: - buildTitlePrompt

    @Test func titlePromptStructure() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let systemMsgs = messages.filter { $0.role == .system }
        let userMsgs = messages.filter { $0.role == .user }
        #expect(systemMsgs.count == 1)
        #expect(userMsgs.count == 1)
        #expect(systemMsgs[0].cacheHint == true)
        #expect(fullText(messages).contains("title"))
    }
}
