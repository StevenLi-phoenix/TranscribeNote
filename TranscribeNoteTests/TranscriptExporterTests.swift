import Testing
import Foundation
import AppKit
@testable import TranscribeNote

@Suite(.serialized)
struct TranscriptExporterTests {

    @Test func formatEmptySegments() {
        let text = TranscriptExporter.formatAsText(segments: [])
        #expect(text == "")
    }

    @Test func formatEmptySegmentsWithTitle() {
        let text = TranscriptExporter.formatAsText(segments: [], title: "My Session")
        #expect(text == "My Session\n")
    }

    @Test func formatSingleSegment() {
        let segment = TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Hello world")
        let text = TranscriptExporter.formatAsText(segments: [segment])
        #expect(text == "[00:00] Hello world")
    }

    @Test func formatMultipleSegments() {
        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Hello world"),
            TranscriptSegment(startTime: 5.0, endTime: 10.0, text: "How are you"),
            TranscriptSegment(startTime: 65.0, endTime: 70.0, text: "One minute in"),
        ]
        let text = TranscriptExporter.formatAsText(segments: segments)
        let expected = """
        [00:00] Hello world
        [00:05] How are you
        [01:05] One minute in
        """
        #expect(text == expected)
    }

    @Test func formatWithTitle() {
        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Hello world"),
        ]
        let text = TranscriptExporter.formatAsText(segments: segments, title: "Meeting Notes")
        let expected = """
        Meeting Notes

        [00:00] Hello world
        """
        #expect(text == expected)
    }

    @Test func copyToClipboardSetsContent() {
        let saved = NSPasteboard.general.string(forType: .string)
        defer { restorePasteboard(saved) }

        let segments = [
            TranscriptSegment(startTime: 0.0, endTime: 5.0, text: "Test clipboard"),
        ]
        TranscriptExporter.copyToClipboard(segments: segments, title: "Test")

        let content = NSPasteboard.general.string(forType: .string)
        #expect(content == "Test\n\n[00:00] Test clipboard")
    }

    private func restorePasteboard(_ saved: String?) {
        NSPasteboard.general.clearContents()
        if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }
}
