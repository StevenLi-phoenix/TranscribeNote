import AppKit

enum TranscriptExporter {
    static func formatAsText(segments: [TranscriptSegment], title: String = "") -> String {
        var lines: [String] = []
        if !title.isEmpty {
            lines.append(title)
            lines.append("")
        }
        for segment in segments {
            let timestamp = segment.startTime.mmss
            lines.append("[\(timestamp)] \(segment.text)")
        }
        return lines.joined(separator: "\n")
    }

    static func copyToClipboard(segments: [TranscriptSegment], title: String = "") {
        let text = formatAsText(segments: segments, title: title)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
