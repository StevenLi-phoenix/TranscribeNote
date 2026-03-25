import Testing
import Foundation
import AppKit
@testable import notetaker

@Suite("TranscriptExporter Extended Tests", .serialized)
struct TranscriptExporterExtendedTests {

    // MARK: - formatAsText with title variations

    @Test func formatWithExplicitEmptyTitle() {
        let segment = TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Hello")
        let text = TranscriptExporter.formatAsText(segments: [segment], title: "")
        #expect(text == "[00:00] Hello")
        // Empty title should not produce a header or blank line
        #expect(!text.hasPrefix("\n"))
    }

    @Test func formatWithWhitespaceOnlyTitle() {
        // Whitespace-only title is technically non-empty, so it should appear as header
        let segment = TranscriptSegment(startTime: 0.0, endTime: 3.0, text: "Content")
        let text = TranscriptExporter.formatAsText(segments: [segment], title: "   ")
        #expect(text.hasPrefix("   \n"))
        #expect(text.contains("[00:00] Content"))
    }

    @Test func formatWithTitleAndMultipleSegments() {
        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "First"),
            TranscriptSegment(startTime: 10.0, endTime: 15.0, text: "Second"),
            TranscriptSegment(startTime: 120.0, endTime: 125.0, text: "Third"),
        ]
        let text = TranscriptExporter.formatAsText(segments: segments, title: "Weekly Standup")
        let expected = """
        Weekly Standup

        [00:00] First
        [00:10] Second
        [02:00] Third
        """
        #expect(text == expected)
    }

    @Test func formatWithoutTitleDefaultsToEmpty() {
        let segment = TranscriptSegment(startTime: 30.0, endTime: 35.0, text: "Half minute")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        // No title header, just the segment line
        #expect(text == "[00:30] Half minute")
    }

    // MARK: - Empty segments edge cases

    @Test func formatEmptySegmentsNoTitleIsEmptyString() {
        let text = TranscriptExporter.formatAsText(segments: [], title: "")
        #expect(text == "")
    }

    @Test func formatEmptySegmentsWithTitleProducesHeaderOnly() {
        let text = TranscriptExporter.formatAsText(segments: [], title: "Empty Meeting")
        // Title + blank line, no segment lines
        #expect(text == "Empty Meeting\n")
    }

    // MARK: - Timestamp formatting for different time ranges

    @Test func formatSegmentAtExactlyOneMinute() {
        let segment = TranscriptSegment(startTime: 60.0, endTime: 65.0, text: "At one minute")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[01:00] At one minute")
    }

    @Test func formatSegmentAtLargeTimestamp() {
        // 1 hour, 30 minutes, 45 seconds = 5445 seconds
        let segment = TranscriptSegment(startTime: 5445.0, endTime: 5450.0, text: "Late in recording")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        // mmss format: 5445 / 60 = 90 minutes, 45 seconds => "90:45"
        #expect(text == "[90:45] Late in recording")
    }

    @Test func formatSegmentAtZeroTime() {
        let segment = TranscriptSegment(startTime: 0.0, endTime: 1.0, text: "Start")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[00:00] Start")
    }

    @Test func formatSegmentWithFractionalSeconds() {
        // 65.9 seconds should truncate to 65 => 01:05
        let segment = TranscriptSegment(startTime: 65.9, endTime: 70.0, text: "Fractional")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[01:05] Fractional")
    }

    @Test func formatSegmentWithSubSecondStartTime() {
        // 0.5 seconds truncates to 0 => 00:00
        let segment = TranscriptSegment(startTime: 0.5, endTime: 1.5, text: "Sub-second")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[00:00] Sub-second")
    }

    @Test func formatSegmentsWithVaryingTimeGaps() {
        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 2.0, text: "Intro"),
            TranscriptSegment(startTime: 2.0, endTime: 4.0, text: "Quick follow"),
            TranscriptSegment(startTime: 300.0, endTime: 310.0, text: "After long pause"),
            TranscriptSegment(startTime: 3661.0, endTime: 3670.0, text: "Over an hour"),
        ]
        let text = TranscriptExporter.formatAsText(segments: segments)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0] == "[00:00] Intro")
        #expect(lines[1] == "[00:02] Quick follow")
        #expect(lines[2] == "[05:00] After long pause")
        // 3661s = 61 minutes 1 second => "61:01"
        #expect(lines[3] == "[61:01] Over an hour")
    }

    // MARK: - Special characters in segment text

    @Test func formatSegmentWithUnicodeCharacters() {
        let segment = TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Caf\u{00E9} r\u{00E9}sum\u{00E9}")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[00:00] Caf\u{00E9} r\u{00E9}sum\u{00E9}")
    }

    @Test func formatSegmentWithCJKCharacters() {
        let segment = TranscriptSegment(startTime: 10.0, endTime: 15.0, text: "\u{4F1A}\u{8BAE}\u{8BB0}\u{5F55}")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[00:10] \u{4F1A}\u{8BAE}\u{8BB0}\u{5F55}")
    }

    @Test func formatSegmentWithNewlinesInText() {
        let segment = TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Line one\nLine two")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        // The segment text contains a newline — formatAsText does not escape it
        #expect(text == "[00:00] Line one\nLine two")
    }

    @Test func formatSegmentWithSpecialPunctuation() {
        let segment = TranscriptSegment(
            startTime: 0.0,
            endTime: 5.0,
            text: "He said \"hello\" & she said 'goodbye' — then left..."
        )
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text.contains("\"hello\""))
        #expect(text.contains("&"))
        #expect(text.contains("\u{2014}"))
        #expect(text.contains("..."))
    }

    @Test func formatSegmentWithEmptyText() {
        let segment = TranscriptSegment(startTime: 5.0, endTime: 10.0, text: "")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[00:05] ")
    }

    // MARK: - Very long text

    @Test func formatSegmentWithVeryLongText() {
        let longText = String(repeating: "word ", count: 1000).trimmingCharacters(in: .whitespaces)
        let segment = TranscriptSegment(startTime: 0.0, endTime: 60.0, text: longText)
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text.hasPrefix("[00:00] word word"))
        #expect(text.contains(longText))
    }

    @Test func formatManySegments() {
        let segments = (0..<100).map { i in
            TranscriptSegment(
                startTime: Double(i) * 5.0,
                endTime: Double(i) * 5.0 + 4.0,
                text: "Segment \(i)"
            )
        }
        let text = TranscriptExporter.formatAsText(segments: segments)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 100)
        // First segment
        #expect(lines[0] == "[00:00] Segment 0")
        // Last segment: 99 * 5 = 495s = 8 min 15 sec
        #expect(lines[99] == "[08:15] Segment 99")
    }

    // MARK: - Title with special characters

    @Test func formatWithTitleContainingSpecialCharacters() {
        let segment = TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Content")
        let text = TranscriptExporter.formatAsText(
            segments: [segment],
            title: "Meeting @ HQ \u{2014} Q4 Planning (Draft #2)"
        )
        #expect(text.hasPrefix("Meeting @ HQ \u{2014} Q4 Planning (Draft #2)\n"))
        #expect(text.hasSuffix("[00:00] Content"))
    }

    // MARK: - copyToClipboard extended tests

    @Test func copyToClipboardWithNoTitle() {
        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "No title copy"),
        ]
        TranscriptExporter.copyToClipboard(segments: segments)

        let content = NSPasteboard.general.string(forType: .string)
        #expect(content == "[00:00] No title copy")
    }

    @Test func copyToClipboardEmptySegments() {
        // First set something so we can verify it gets replaced
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("previous content", forType: .string)

        TranscriptExporter.copyToClipboard(segments: [])

        let content = NSPasteboard.general.string(forType: .string)
        #expect(content == "")
    }

    @Test func copyToClipboardOverwritesPreviousContent() {
        // Set initial content
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("old content", forType: .string)

        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "New content"),
        ]
        TranscriptExporter.copyToClipboard(segments: segments, title: "Fresh")

        let content = NSPasteboard.general.string(forType: .string)
        #expect(content == "Fresh\n\n[00:00] New content")
        #expect(content != "old content")
    }

    @Test func copyToClipboardMultipleSegmentsWithTitle() {
        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 10.0, text: "First line"),
            TranscriptSegment(startTime: 10.0, endTime: 20.0, text: "Second line"),
        ]
        TranscriptExporter.copyToClipboard(segments: segments, title: "Notes")

        let content = NSPasteboard.general.string(forType: .string)
        let expected = """
        Notes

        [00:00] First line
        [00:10] Second line
        """
        #expect(content == expected)
    }

    // MARK: - Segment ordering (exporter uses array order, not sorted by time)

    @Test func formatPreservesSegmentArrayOrder() {
        // Segments intentionally out of chronological order
        let segments = [
            TranscriptSegment(startTime: 60.0, endTime: 65.0, text: "Later"),
            TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Earlier"),
        ]
        let text = TranscriptExporter.formatAsText(segments: segments)
        let lines = text.split(separator: "\n").map(String.init)
        // Should preserve array order, not sort by time
        #expect(lines[0] == "[01:00] Later")
        #expect(lines[1] == "[00:00] Earlier")
    }
}
