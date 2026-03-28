import Foundation
import Testing
@testable import notetaker

@Suite("DragDropExport")
struct DragDropExportTests {

    @Test func plainTextFormat_includesTitle() {
        let item = SessionExportInfo(
            title: "Test Meeting",
            startedAt: Date(),
            segments: [(startTime: 0, text: "Hello world")],
            summaryContent: nil
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("# Test Meeting"))
        #expect(text.contains("00:00  Hello world"))
    }

    @Test func plainTextFormat_includesSummary() {
        let item = SessionExportInfo(
            title: "Test",
            startedAt: Date(),
            segments: [],
            summaryContent: "Meeting summary"
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("## Summary"))
        #expect(text.contains("Meeting summary"))
    }

    @Test func plainTextFormat_emptyContent() {
        let item = SessionExportInfo(
            title: "Empty",
            startedAt: Date(),
            segments: [],
            summaryContent: nil
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("# Empty"))
        #expect(!text.contains("## Summary"))
        #expect(!text.contains("## Transcript"))
    }

    @Test func plainTextFormat_multipleSegments() {
        let item = SessionExportInfo(
            title: "Multi",
            startedAt: Date(),
            segments: [
                (startTime: 0, text: "First"),
                (startTime: 60, text: "Second"),
                (startTime: 125, text: "Third"),
            ],
            summaryContent: nil
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("00:00  First"))
        #expect(text.contains("01:00  Second"))
        #expect(text.contains("02:05  Third"))
    }

    @Test func timeFormatting_largeValues() {
        let item = SessionExportInfo(
            title: "T",
            startedAt: Date(),
            segments: [(startTime: 3661, text: "Late")],
            summaryContent: nil
        )
        let text = item.formatAsPlainText()
        // 3661 seconds = 61 min 1 sec
        #expect(text.contains("61:01  Late"))
    }

    @Test func plainTextFormat_summaryAndTranscript() {
        let item = SessionExportInfo(
            title: "Full Session",
            startedAt: Date(),
            segments: [
                (startTime: 0, text: "Hello"),
                (startTime: 30, text: "World"),
            ],
            summaryContent: "A brief discussion"
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("# Full Session"))
        #expect(text.contains("## Summary"))
        #expect(text.contains("A brief discussion"))
        #expect(text.contains("## Transcript"))
        #expect(text.contains("00:00  Hello"))
        #expect(text.contains("00:30  World"))
    }

    @Test func plainTextFormat_emptySummaryExcluded() {
        let item = SessionExportInfo(
            title: "No Summary",
            startedAt: Date(),
            segments: [(startTime: 0, text: "Words")],
            summaryContent: ""
        )
        let text = item.formatAsPlainText()
        #expect(!text.contains("## Summary"))
    }

    @Test func plainTextFormat_dateIncluded() {
        let date = Date(timeIntervalSince1970: 0)
        let item = SessionExportInfo(
            title: "Dated",
            startedAt: date,
            segments: [],
            summaryContent: nil
        )
        let text = item.formatAsPlainText()
        // Date should appear on second line (formatted)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count >= 2)
        #expect(!lines[1].isEmpty)
    }
}
