import Foundation
import Testing
@testable import notetaker

struct MarkdownExporterTests {

    // MARK: - Frontmatter

    @Test func testFrontmatterBasic() {
        let date = Date(timeIntervalSince1970: 1_711_612_200) // 2024-03-28T14:30:00+00:00
        let result = MarkdownExporter.generateFrontmatter(
            title: "My Session",
            date: date,
            totalDuration: 5025,
            segmentsCount: 87,
            tags: ["meeting"]
        )
        #expect(result.hasPrefix("---\n"))
        #expect(result.hasSuffix("---\n"))
        #expect(result.contains("title: \"My Session\""))
        #expect(result.contains("duration: \"01:23:45\""))
        #expect(result.contains("duration_seconds: 5025"))
        #expect(result.contains("type: meeting-note"))
        #expect(result.contains("source: notetaker"))
        #expect(result.contains("segments_count: 87"))
        #expect(result.contains("tags:"))
        #expect(result.contains("  - meeting"))
        #expect(result.contains("date: "))
    }

    @Test func testFrontmatterEscapesQuotes() {
        let result = MarkdownExporter.generateFrontmatter(
            title: "He said \"hello\"",
            date: Date(),
            totalDuration: 60,
            segmentsCount: 1,
            tags: []
        )
        #expect(result.contains("title: \"He said \\\"hello\\\"\""))
    }

    @Test func testFrontmatterEscapesColons() {
        let result = MarkdownExporter.generateFrontmatter(
            title: "Meeting: Important",
            date: Date(),
            totalDuration: 60,
            segmentsCount: 1,
            tags: []
        )
        // Title with colons should be quoted (it already is)
        #expect(result.contains("title: \"Meeting: Important\""))
    }

    @Test func testFrontmatterNoTags() {
        let result = MarkdownExporter.generateFrontmatter(
            title: "Test",
            date: Date(),
            totalDuration: 60,
            segmentsCount: 1,
            tags: []
        )
        #expect(!result.contains("tags:"))
    }

    // MARK: - Summaries

    @Test func testFormatSummariesOverallAndChunks() {
        let summaries: [MarkdownExporter.SummaryInfo] = [
            .init(content: "Chunk B", coveringFrom: 300, coveringTo: 600, isOverall: false),
            .init(content: "Overall content", coveringFrom: 0, coveringTo: 600, isOverall: true),
            .init(content: "Chunk A", coveringFrom: 0, coveringTo: 300, isOverall: false),
        ]
        let result = MarkdownExporter.formatSummaries(summaries)
        let overallIndex = result.range(of: "Overall content")!.lowerBound
        let chunkAIndex = result.range(of: "Chunk A")!.lowerBound
        let chunkBIndex = result.range(of: "Chunk B")!.lowerBound
        // Overall comes first
        #expect(overallIndex < chunkAIndex)
        // Chunks sorted by time
        #expect(chunkAIndex < chunkBIndex)
        // Section headers
        #expect(result.contains("## Overall Summary"))
        #expect(result.contains("## 00:00–05:00"))
        #expect(result.contains("## 05:00–10:00"))
    }

    @Test func testFormatSummariesEmpty() {
        let result = MarkdownExporter.formatSummaries([])
        #expect(result.isEmpty)
    }

    // MARK: - Transcript

    @Test func testFormatTranscriptTimestamped() {
        let segments: [MarkdownExporter.SegmentInfo] = [
            .init(startTime: 0, text: "Hello"),
            .init(startTime: 65, text: "World"),
        ]
        let result = MarkdownExporter.formatTranscript(segments, format: .timestamped)
        #expect(result.contains("[00:00] Hello"))
        #expect(result.contains("[01:05] World"))
    }

    @Test func testFormatTranscriptTable() {
        let segments: [MarkdownExporter.SegmentInfo] = [
            .init(startTime: 0, text: "Hello"),
            .init(startTime: 65, text: "World"),
        ]
        let result = MarkdownExporter.formatTranscript(segments, format: .table)
        #expect(result.contains("| Time | Content |"))
        #expect(result.contains("|------|---------|"))
        #expect(result.contains("| 00:00 | Hello |"))
        #expect(result.contains("| 01:05 | World |"))
    }

    // MARK: - Sanitize

    @Test func testSanitizeFilename() {
        #expect(MarkdownExporter.sanitizeFilename("My/File:Name*Test") == "MyFileNameTest")
        #expect(MarkdownExporter.sanitizeFilename("normal-file_name") == "normal-file_name")
        #expect(MarkdownExporter.sanitizeFilename("") == "untitled")
        #expect(MarkdownExporter.sanitizeFilename("a\"b<c>d|e?f\\g") == "abcdefg")
    }

    // MARK: - Full export

    @Test func testExportFullDocument() {
        let segments: [MarkdownExporter.SegmentInfo] = [
            .init(startTime: 0, text: "Hello"),
        ]
        let summaries: [MarkdownExporter.SummaryInfo] = [
            .init(content: "Summary text", coveringFrom: 0, coveringTo: 60, isOverall: true),
        ]
        let result = MarkdownExporter.export(
            title: "Test Session",
            date: Date(),
            totalDuration: 60,
            segments: segments,
            summaries: summaries,
            options: .init()
        )
        // Should have frontmatter, summary section, transcript section
        #expect(result.hasPrefix("---\n"))
        #expect(result.contains("# Summary"))
        #expect(result.contains("Summary text"))
        #expect(result.contains("# Transcript"))
        #expect(result.contains("[00:00] Hello"))
    }

    @Test func testExportWithoutFrontmatter() {
        let result = MarkdownExporter.export(
            title: "Test",
            date: Date(),
            totalDuration: 60,
            segments: [.init(startTime: 0, text: "Hi")],
            summaries: [],
            options: .init(includeYAMLFrontmatter: false)
        )
        #expect(!result.hasPrefix("---\n"))
        #expect(result.contains("# Transcript"))
    }

    @Test func testExportWithoutSummary() {
        let summaries: [MarkdownExporter.SummaryInfo] = [
            .init(content: "Should not appear", coveringFrom: 0, coveringTo: 60, isOverall: true),
        ]
        let result = MarkdownExporter.export(
            title: "Test",
            date: Date(),
            totalDuration: 60,
            segments: [.init(startTime: 0, text: "Hi")],
            summaries: summaries,
            options: .init(includeSummary: false)
        )
        #expect(!result.contains("# Summary"))
        #expect(!result.contains("Should not appear"))
        #expect(result.contains("# Transcript"))
    }
}
