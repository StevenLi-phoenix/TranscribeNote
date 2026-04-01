import Testing
import Foundation
@testable import TranscribeNote

@Suite("PromptBuilder Extended Tests")
struct PromptBuilderExtendedTests {
    private func makeSegment(startTime: TimeInterval, endTime: TimeInterval, text: String) -> TranscriptSegment {
        TranscriptSegment(startTime: startTime, endTime: endTime, text: text)
    }

    private func fullText(_ messages: [LLMMessage]) -> String {
        messages.map(\.content).joined(separator: "\n\n")
    }

    private func systemContent(_ messages: [LLMMessage]) -> String {
        messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
    }

    private func userContent(_ messages: [LLMMessage]) -> String {
        messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")
    }

    // MARK: - buildOverallSummaryPrompt extended

    @Test func overallPromptWithMultipleChunks() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 300, content: "Introduction and agenda"),
            (coveringFrom: 300, coveringTo: 600, content: "Technical discussion on API design"),
            (coveringFrom: 600, coveringTo: 900, content: "Action items and next steps"),
        ]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let text = fullText(messages)
        #expect(text.contains("[00:00 – 05:00]"))
        #expect(text.contains("[05:00 – 10:00]"))
        #expect(text.contains("[10:00 – 15:00]"))
        #expect(text.contains("Introduction and agenda"))
        #expect(text.contains("Technical discussion on API design"))
        #expect(text.contains("Action items and next steps"))
        #expect(text.contains("<summaries>"))
    }

    @Test func overallPromptWithEmptyChunks() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = []
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        // Should still have system message
        let systemMsgs = messages.filter { $0.role == .system }
        #expect(systemMsgs.count == 1)
        // No user message with section summaries
        // System message mentions <summaries> tags in instructions, but no actual summaries block
        let userMessages = messages.filter { $0.role == .user }
        let userText = userMessages.map(\.content).joined()
        #expect(!userText.contains("<summaries>"))
    }

    @Test func overallPromptParagraphStyle() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Summary text"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .paragraph

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let text = fullText(messages)
        #expect(text.contains("paragraph"))
        #expect(text.contains("Synthesize"))
    }

    @Test func overallPromptActionItemsStyle() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 120, content: "Review code changes"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .actionItems

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let text = fullText(messages)
        #expect(text.contains("checklist") || text.contains("action items"))
        #expect(text.contains("- [ ]"))
    }

    @Test func overallPromptBulletsStyle() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Bullet summary"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .bullets

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let text = fullText(messages)
        #expect(text.contains("bullet points"))
        #expect(text.contains("meeting/note summarizer"))
    }

    @Test func overallPromptContainsNoPreambleConstraint() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Summary"),
        ]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("Output ONLY the summary content"))
        #expect(sys.contains("Do not include any preamble"))
    }

    @Test func overallPromptLectureNotesUsesStructuredNotesTask() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Lecture content"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("structured notes"))
    }

    @Test func overallPromptNonLectureUsesCohesiveTask() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Meeting summary"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .bullets

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("cohesive overall summary"))
    }

    // MARK: - buildTitlePrompt extended

    @Test func titlePromptContainsTitleGenerator() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Discussion about project")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("title generator"))
        #expect(sys.contains("5-10 words"))
    }

    @Test func titlePromptWithLanguageConstraint() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Discussion")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "French"

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("French"))
        #expect(sys.contains("Write the title in"))
    }

    @Test func titlePromptNoLanguageWhenAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Discussion")]
        let config = SummarizerConfig.default // summaryLanguage = "auto"

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let sys = systemContent(messages)
        #expect(!sys.contains("Write the title in"))
    }

    @Test func titlePromptWithEmptySegments() {
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildTitlePrompt(segments: [], config: config)
        // Should still have system message
        let systemMsgs = messages.filter { $0.role == .system }
        #expect(systemMsgs.count == 1)
        // No transcript user message
        let userMsgs = messages.filter { $0.role == .user }
        #expect(userMsgs.isEmpty)
    }

    @Test func titlePromptTruncatesAtFiftySegments() {
        var segments: [TranscriptSegment] = []
        for i in 0..<70 {
            segments.append(makeSegment(
                startTime: Double(i * 10),
                endTime: Double(i * 10 + 5),
                text: "Segment number \(i)"
            ))
        }
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let text = userContent(messages)
        // Should contain the first 50 segments
        #expect(text.contains("Segment number 0"))
        #expect(text.contains("Segment number 49"))
        // Should NOT contain segment 50+
        #expect(!text.contains("Segment number 50"))
        // Should indicate truncation
        #expect(text.contains("20 more segments"))
    }

    @Test func titlePromptFormatsTimestamps() {
        let segments = [
            makeSegment(startTime: 90, endTime: 95, text: "One thirty"),
            makeSegment(startTime: 3661, endTime: 3665, text: "Over an hour"),
        ]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let text = userContent(messages)
        #expect(text.contains("[01:30]"))
        #expect(text.contains("One thirty"))
    }

    @Test func titlePromptSystemHasCacheHint() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Test")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let sys = messages.first { $0.role == .system }!
        #expect(sys.cacheHint == true)
    }

    @Test func titlePromptOutputInstructionsNoPreamble() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Test")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("ONLY the title text"))
        #expect(sys.contains("Do not include quotes"))
    }

    // MARK: - sanitizeLanguage (tested indirectly via language constraint)

    @Test func languageWithNewlinesIsStripped() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Japa\nnese"

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        // Newline should be replaced with space, then only letters/spaces kept
        #expect(sys.contains("Japa nese") || sys.contains("Japanese"))
        #expect(!sys.contains("Japa\nnese"))
    }

    @Test func languageWithCarriageReturnIsStripped() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Span\rish"

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        #expect(!sys.contains("\r"))
        #expect(sys.contains("Span ish") || sys.contains("Spanish"))
    }

    @Test func languageTruncatedAt50Characters() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        // 60 letter characters
        config.summaryLanguage = String(repeating: "a", count: 60)

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        // Count occurrences of the repeated character in the language instruction
        let fiftyAs = String(repeating: "a", count: 50)
        let sixtyAs = String(repeating: "a", count: 60)
        #expect(sys.contains(fiftyAs))
        #expect(!sys.contains(sixtyAs))
    }

    @Test func languageEmptyStringTreatedAsNonAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = ""

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        // Empty string != "auto", so language constraint triggers but with empty language
        // The constraint block fires because "" != "auto"
        #expect(sys.contains("MUST write the entire response in"))
    }

    @Test func languageWithSpecialCharactersFiltered() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "English!@#$%^&*()"

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        // Only letters and spaces should survive sanitization
        #expect(sys.contains("English"))
        #expect(!sys.contains("!@#"))
    }

    @Test func languageWithNumbersFiltered() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "English123"

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        // Numbers should be stripped (only letters + spaces pass)
        #expect(sys.contains("English"))
        #expect(!sys.contains("123"))
    }

    // MARK: - sanitizeInstructions (tested indirectly via additionalInstructions)

    @Test func instructionsWithCarriageReturnStripped() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "First\rSecond"
        )
        let text = fullText(messages)
        #expect(!text.contains("\r"))
        #expect(text.contains("First Second"))
    }

    @Test func instructionsWithLeadingTrailingWhitespace() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "  Focus on details  "
        )
        let instructionMsg = messages.first { $0.role == .user && $0.content.contains("Additional user instructions") }!
        #expect(instructionMsg.content.contains("Focus on details"))
    }

    @Test func instructionsExactly500CharsNotTruncated() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default
        let exact500 = String(repeating: "z", count: 500)

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: exact500
        )
        let instructionMsg = messages.first { $0.role == .user && $0.content.contains("Additional user instructions") }!
        let zCount = instructionMsg.content.filter { $0 == "z" }.count
        #expect(zCount == 500)
    }

    // MARK: - constraintBlock (tested indirectly)

    @Test func constraintBlockAlwaysPresent() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("Output ONLY the summary content"))
        #expect(sys.contains("Do not include any preamble"))
    }

    @Test func constraintBlockIncludesLanguageWhenNonAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "German"

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("MUST write the entire response in German"))
        #expect(sys.contains("Do not use any other language"))
    }

    @Test func constraintBlockOmitsLanguageWhenAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        #expect(!sys.contains("MUST write the entire response in"))
    }

    // MARK: - SummaryStyle variations in buildSummarizationPrompt

    @Test func lectureNotesTaskUsesNotesLanguage() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let sys = systemContent(messages)
        // lectureNotes uses "Create detailed, structured notes" task
        #expect(sys.contains("detailed, structured notes"))
        #expect(sys.contains("key concept"))
        #expect(sys.contains("nested bullets"))
    }

    @Test func nonLectureStyleUsesTranscriptSummaryTask() {
        for style: SummaryStyle in [.bullets, .paragraph, .actionItems] {
            let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
            var config = SummarizerConfig.default
            config.summaryStyle = style

            let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
            let sys = systemContent(messages)
            #expect(sys.contains("Summarize the following transcript"))
        }
    }

    // MARK: - Previous summary edge cases

    @Test func emptyPreviousSummaryStringExcluded() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "", config: config)
        let text = fullText(messages)
        #expect(!text.contains("Previous summary for context:"))
        #expect(!text.contains("Previous notes for context:"))
    }

    @Test func previousSummaryTruncatedToMaxContextTokens() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = true
        config.maxContextTokens = 10

        let longSummary = String(repeating: "w", count: 50)

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: longSummary, config: config)
        let contextMsg = messages.first { $0.role == .user && $0.content.contains("Previous summary") }!
        let wCount = contextMsg.content.filter { $0 == "w" }.count
        #expect(wCount == 10)
    }

    @Test func previousSummaryNilDoesNotAddContextMessage() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let text = fullText(messages)
        #expect(!text.contains("Previous summary for context:"))
    }

    // MARK: - Message ordering

    @Test func messageOrderIsSystemThenInstructionsThenContextThenTranscript() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Transcript text")]
        var config = SummarizerConfig.default
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: "Previous context",
            config: config,
            additionalInstructions: "Extra instructions"
        )

        #expect(messages.count == 4)
        #expect(messages[0].role == .system)
        #expect(messages[1].content.contains("Additional user instructions"))
        #expect(messages[2].content.contains("Previous"))
        #expect(messages[3].content.contains("<transcript>"))
    }

    // MARK: - Edge cases with multiple segments

    @Test func multipleSegmentsFormattedCorrectly() {
        let segments = [
            makeSegment(startTime: 0, endTime: 10, text: "First point"),
            makeSegment(startTime: 10, endTime: 20, text: "Second point"),
            makeSegment(startTime: 20, endTime: 30, text: "Third point"),
        ]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let text = userContent(messages)
        #expect(text.contains("[00:00] First point"))
        #expect(text.contains("[00:10] Second point"))
        #expect(text.contains("[00:20] Third point"))
    }

    @Test func singleSegmentHasTranscriptLabel() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Only segment")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        let text = userContent(messages)
        #expect(text.contains("<transcript>"))
        #expect(text.contains("Only segment"))
    }

    // MARK: - Language constraint in overall and title prompts

    @Test func overallPromptLanguageSanitized() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Summary"),
        ]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Chinese\nSimplified"

        let messages = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        let sys = systemContent(messages)
        #expect(!sys.contains("\n" + "Simplified"))
        #expect(sys.contains("MUST write the entire response in"))
    }

    @Test func titlePromptLanguageSanitized() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Test")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Korean!@#"

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        let sys = systemContent(messages)
        #expect(sys.contains("Korean"))
        #expect(!sys.contains("!@#"))
    }

    // MARK: - Guided regeneration (via additionalInstructions in buildSummarizationPrompt)

    @Test func guidedRegenerationInstructionsInUserMessage() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Meeting about product launch")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "Focus on deadlines and responsible parties"
        )

        // Instructions should be in user message, not system
        let instructionMsg = messages.first { $0.role == .user && $0.content.contains("Additional user instructions") }
        #expect(instructionMsg != nil)
        #expect(instructionMsg!.content.contains("Focus on deadlines and responsible parties"))
    }

    @Test func guidedRegenerationWithAllOptions() {
        let segments = [
            makeSegment(startTime: 0, endTime: 30, text: "We need to ship by Friday"),
            makeSegment(startTime: 30, endTime: 60, text: "Alice will handle the deployment"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .actionItems
        config.summaryLanguage = "Spanish"
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: "Previous action items",
            config: config,
            additionalInstructions: "Highlight urgency"
        )

        let text = fullText(messages)
        // All components present
        #expect(text.contains("checklist") || text.contains("action items"))
        #expect(text.contains("Spanish"))
        #expect(text.contains("Previous action items"))
        #expect(text.contains("Highlight urgency"))
        #expect(text.contains("ship by Friday"))
        #expect(text.contains("Alice will handle"))
    }

    // MARK: - buildSummarizationPrompt message count variations

    @Test func messageCountWithAllOptions() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = true

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: "Context",
            config: config,
            additionalInstructions: "Extra"
        )
        // system + instructions + context + transcript = 4
        #expect(messages.count == 4)
    }

    @Test func messageCountMinimal() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config
        )
        // system + transcript = 2
        #expect(messages.count == 2)
    }

    @Test func messageCountEmptySegmentsNoContext() {
        let config = SummarizerConfig.default

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: [],
            previousSummary: nil,
            config: config
        )
        // system only = 1
        #expect(messages.count == 1)
    }
}
