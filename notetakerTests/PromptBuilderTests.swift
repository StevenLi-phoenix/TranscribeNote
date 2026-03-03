import Testing
import Foundation
@testable import notetaker

struct PromptBuilderTests {
    private func makeSegment(startTime: TimeInterval, endTime: TimeInterval, text: String) -> TranscriptSegment {
        TranscriptSegment(startTime: startTime, endTime: endTime, text: text)
    }

    @Test func bulletsStyleContainsBulletPoints() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .bullets

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(prompt.contains("bullet points"))
    }

    @Test func paragraphStyleContainsParagraph() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .paragraph

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(prompt.contains("paragraph"))
    }

    @Test func actionItemsStyleContainsChecklist() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .actionItems

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(prompt.contains("checklist") || prompt.contains("action items"))
    }

    @Test func includesPreviousSummary() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = true

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Previous notes here", config: config)
        #expect(prompt.contains("Previous notes here"))
    }

    @Test func excludesPreviousSummaryWhenDisabled() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.includeContext = false

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Previous notes here", config: config)
        #expect(!prompt.contains("Previous notes here"))
    }

    @Test func languageInstructionWhenNotAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Japanese"

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(prompt.contains("Japanese"))
    }

    @Test func noLanguageInstructionWhenAuto() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(!prompt.contains("Respond in"))
    }

    @Test func segmentsFormattedWithTimestamps() {
        let segments = [
            makeSegment(startTime: 65, endTime: 70, text: "First segment"),
            makeSegment(startTime: 130, endTime: 135, text: "Second segment"),
        ]
        let config = SummarizerConfig.default

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(prompt.contains("[01:05] First segment"))
        #expect(prompt.contains("[02:10] Second segment"))
    }

    @Test func emptySegmentsDoesNotCrash() {
        let config = SummarizerConfig.default
        let prompt = PromptBuilder.buildSummarizationPrompt(segments: [], previousSummary: nil, config: config)
        #expect(!prompt.isEmpty)
        #expect(!prompt.contains("Transcript:"))
    }

    @Test func lectureNotesStyleContainsDetailedInstructions() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello world")]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: nil, config: config)
        #expect(prompt.contains("lecture note-taker"))
        #expect(prompt.contains("**Topic:**"))
    }

    @Test func lectureNotesUsesNotesContextLabel() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes
        config.includeContext = true

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Prior notes", config: config)
        #expect(prompt.contains("Previous notes for context:"))
        #expect(prompt.contains("Prior notes"))
    }

    @Test func bulletsStyleUsesSummaryContextLabel() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        var config = SummarizerConfig.default
        config.summaryStyle = .bullets
        config.includeContext = true

        let prompt = PromptBuilder.buildSummarizationPrompt(segments: segments, previousSummary: "Previous data", config: config)
        #expect(prompt.contains("Previous summary for context:"))
    }

    // MARK: - additionalInstructions

    @Test func additionalInstructionsAppearInPrompt() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let prompt = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "Focus on action items"
        )
        #expect(prompt.contains("Additional user instructions:"))
        #expect(prompt.contains("Focus on action items"))
    }

    @Test func additionalInstructionsOmittedWhenNil() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let prompt = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: nil
        )
        #expect(!prompt.contains("Additional user instructions"))
    }

    @Test func additionalInstructionsOmittedWhenEmpty() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let prompt = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: ""
        )
        #expect(!prompt.contains("Additional user instructions"))
    }

    @Test func additionalInstructionsSanitized() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default

        let prompt = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: "Line1\nLine2\rLine3"
        )
        // Newlines should be replaced with spaces
        #expect(!prompt.contains("Line1\n"))
        #expect(prompt.contains("Line1 Line2 Line3"))
    }

    @Test func additionalInstructionsTruncatedAt500Chars() {
        let segments = [makeSegment(startTime: 0, endTime: 5, text: "Hello")]
        let config = SummarizerConfig.default
        let longInstructions = String(repeating: "x", count: 600)

        let prompt = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: longInstructions
        )
        // Should contain at most 500 x's
        let instructionsLine = prompt.components(separatedBy: "\n\n")
            .first { $0.contains("Additional user instructions") } ?? ""
        let xCount = instructionsLine.filter { $0 == "x" }.count
        #expect(xCount == 500)
    }

    // MARK: - buildOverallSummaryPrompt

    @Test func overallPromptContainsSynthesizeInstruction() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "First section summary"),
            (coveringFrom: 60, coveringTo: 120, content: "Second section summary"),
        ]
        let config = SummarizerConfig.default

        let prompt = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        #expect(prompt.contains("Synthesize"))
        #expect(prompt.contains("First section summary"))
        #expect(prompt.contains("Second section summary"))
        #expect(prompt.contains("[00:00 – 01:00]"))
        #expect(prompt.contains("[01:00 – 02:00]"))
    }

    @Test func overallPromptRespectsLanguage() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Some summary"),
        ]
        var config = SummarizerConfig.default
        config.summaryLanguage = "Japanese"

        let prompt = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        #expect(prompt.contains("Japanese"))
    }

    @Test func overallPromptLectureNotesStyle() {
        let chunks: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = [
            (coveringFrom: 0, coveringTo: 60, content: "Lecture chunk"),
        ]
        var config = SummarizerConfig.default
        config.summaryStyle = .lectureNotes

        let prompt = PromptBuilder.buildOverallSummaryPrompt(chunkSummaries: chunks, config: config)
        #expect(prompt.contains("lecture note-taker"))
        #expect(prompt.contains("**Topic:**"))
        #expect(prompt.contains("Synthesize"))
    }
}
