import Testing
@testable import notetaker

@Suite("SummaryMarkdownFormatter")
struct SummaryMarkdownFormatterTests {

    @Test("Overall summary formats with 'Overall Summary' heading")
    func overallSummaryFormat() {
        let result = SummaryMarkdownFormatter.format(
            content: "Key points from the meeting.",
            coveringFrom: 0,
            coveringTo: 300,
            isOverall: true
        )
        #expect(result == "## Overall Summary\n\nKey points from the meeting.")
    }

    @Test("Chunk summary formats with time range heading")
    func chunkSummaryFormat() {
        let result = SummaryMarkdownFormatter.format(
            content: "Discussion about architecture.",
            coveringFrom: 0,
            coveringTo: 300,
            isOverall: false
        )
        #expect(result == "## 00:00–05:00\n\nDiscussion about architecture.")
    }

    @Test("Chunk summary with non-zero start time")
    func chunkSummaryNonZeroStart() {
        let result = SummaryMarkdownFormatter.format(
            content: "Budget review.",
            coveringFrom: 300,
            coveringTo: 600,
            isOverall: false
        )
        #expect(result == "## 05:00–10:00\n\nBudget review.")
    }

    @Test("Multiline content preserved as-is")
    func multilineContent() {
        let content = "- Point one\n- Point two\n- Point three"
        let result = SummaryMarkdownFormatter.format(
            content: content,
            coveringFrom: 0,
            coveringTo: 120,
            isOverall: true
        )
        #expect(result == "## Overall Summary\n\n- Point one\n- Point two\n- Point three")
    }

    @Test("Empty content produces heading only")
    func emptyContent() {
        let result = SummaryMarkdownFormatter.format(
            content: "",
            coveringFrom: 0,
            coveringTo: 60,
            isOverall: false
        )
        #expect(result == "## 00:00–01:00\n\n")
    }

    @Test("Long duration uses mm:ss format")
    func longDuration() {
        let result = SummaryMarkdownFormatter.format(
            content: "Summary text.",
            coveringFrom: 3600,
            coveringTo: 7200,
            isOverall: false
        )
        // mmss: 3600 -> 60:00, 7200 -> 120:00
        #expect(result == "## 60:00–120:00\n\nSummary text.")
    }
}
