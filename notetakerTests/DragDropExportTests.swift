import Foundation
import Testing
@testable import notetaker

@Suite("DragDropExport")
struct DragDropExportTests {

    @Test func plainTextFormat_includesTitle() {
        let item = SessionExportItem(
            title: "Test Meeting",
            startedAt: Date(),
            totalDuration: 300,
            segments: [
                MarkdownExporter.SegmentInfo(startTime: 0, text: "Hello world")
            ],
            summaries: [],
            tags: []
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("# Test Meeting"))
        #expect(text.contains("[00:00] Hello world"))
    }

    @Test func plainTextFormat_includesSummary() {
        let item = SessionExportItem(
            title: "Test",
            startedAt: Date(),
            totalDuration: 300,
            segments: [],
            summaries: [
                MarkdownExporter.SummaryInfo(
                    content: "Meeting summary",
                    coveringFrom: 0,
                    coveringTo: 300,
                    isOverall: true
                )
            ],
            tags: []
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("## Summary"))
        #expect(text.contains("Meeting summary"))
    }

    @Test func plainTextFormat_emptyContent() {
        let item = SessionExportItem(
            title: "Empty",
            startedAt: Date(),
            totalDuration: 0,
            segments: [],
            summaries: [],
            tags: []
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("# Empty"))
        #expect(!text.contains("## Summary"))
        #expect(!text.contains("## Transcript"))
    }

    @Test func plainTextFormat_multipleSegments() {
        let item = SessionExportItem(
            title: "Multi",
            startedAt: Date(),
            totalDuration: 135,
            segments: [
                MarkdownExporter.SegmentInfo(startTime: 0, text: "First"),
                MarkdownExporter.SegmentInfo(startTime: 60, text: "Second"),
                MarkdownExporter.SegmentInfo(startTime: 125, text: "Third")
            ],
            summaries: [],
            tags: []
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("[00:00] First"))
        #expect(text.contains("[01:00] Second"))
        #expect(text.contains("[02:05] Third"))
    }

    @Test func timeFormatting_largeValues() {
        let item = SessionExportItem(
            title: "T",
            startedAt: Date(),
            totalDuration: 3670,
            segments: [
                MarkdownExporter.SegmentInfo(startTime: 3661, text: "Late")
            ],
            summaries: [],
            tags: []
        )
        let text = item.formatAsPlainText()
        // 3661 seconds = 61 min 1 sec
        #expect(text.contains("[61:01] Late"))
    }

    @Test func plainTextFormat_summaryAndTranscript() {
        let item = SessionExportItem(
            title: "Full Session",
            startedAt: Date(),
            totalDuration: 60,
            segments: [
                MarkdownExporter.SegmentInfo(startTime: 0, text: "Hello"),
                MarkdownExporter.SegmentInfo(startTime: 30, text: "World")
            ],
            summaries: [
                MarkdownExporter.SummaryInfo(
                    content: "A brief discussion",
                    coveringFrom: 0,
                    coveringTo: 60,
                    isOverall: true
                )
            ],
            tags: []
        )
        let text = item.formatAsPlainText()
        #expect(text.contains("# Full Session"))
        #expect(text.contains("## Summary"))
        #expect(text.contains("A brief discussion"))
        #expect(text.contains("## Transcript"))
        #expect(text.contains("[00:00] Hello"))
        #expect(text.contains("[00:30] World"))
    }
}
