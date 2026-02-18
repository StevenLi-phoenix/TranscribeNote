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
}
