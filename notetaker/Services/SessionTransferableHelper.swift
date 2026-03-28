import SwiftUI
import UniformTypeIdentifiers
import os

/// Lightweight transferable wrapper for dragging sessions out of the app.
///
/// Since `RecordingSession` is a SwiftData `@Model` (reference type with MainActor isolation),
/// we snapshot the data into this value type for `Transferable` conformance.
struct SessionExportItem: Transferable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "SessionExportItem"
    )

    let title: String
    let startedAt: Date
    let totalDuration: TimeInterval
    let segments: [MarkdownExporter.SegmentInfo]
    let summaries: [MarkdownExporter.SummaryInfo]
    let tags: [String]

    static var transferRepresentation: some TransferRepresentation {
        // Plain text — drag to text fields, editors, etc.
        DataRepresentation(exportedContentType: .plainText) { item in
            logger.info("Exporting plain text for session: \(item.title)")
            let text = item.formatAsPlainText()
            return Data(text.utf8)
        }

        // Markdown file — drag to Finder, file-accepting apps
        FileRepresentation(exportedContentType: .utf8PlainText) { item in
            let markdown = MarkdownExporter.export(
                title: item.title,
                date: item.startedAt,
                totalDuration: item.totalDuration,
                segments: item.segments,
                summaries: item.summaries,
                options: .init(
                    includeYAMLFrontmatter: true,
                    includeSummary: true,
                    includeTranscript: true,
                    transcriptFormat: .timestamped,
                    customTags: item.tags
                )
            )
            let filename = MarkdownExporter.sanitizeFilename(item.title) + ".md"
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(filename)
            try Data(markdown.utf8).write(to: tempURL)
            logger.info("Exported Markdown file to: \(tempURL.path)")
            return SentTransferredFile(tempURL)
        }
    }

    // MARK: - Plain text formatting

    func formatAsPlainText() -> String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append(startedAt.formatted(date: .abbreviated, time: .shortened))
        lines.append("")

        if !summaries.isEmpty {
            lines.append("## Summary")
            for summary in summaries {
                lines.append(summary.content)
                lines.append("")
            }
        }

        if !segments.isEmpty {
            lines.append("## Transcript")
            for segment in segments {
                let time = formatTime(segment.startTime)
                lines.append("[\(time)] \(segment.text)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Convenience initializer from RecordingSession

extension SessionExportItem {
    /// Create from a RecordingSession (must be called on MainActor).
    @MainActor
    init(session: RecordingSession) {
        self.title = session.title
        self.startedAt = session.startedAt
        self.totalDuration = session.totalDuration
        self.tags = session.tags
        self.segments = session.segments
            .sorted { $0.startTime < $1.startTime }
            .map { MarkdownExporter.SegmentInfo(startTime: $0.startTime, text: $0.text) }
        self.summaries = session.summaries
            .sorted { $0.coveringFrom < $1.coveringFrom }
            .map {
                MarkdownExporter.SummaryInfo(
                    content: $0.displayContent,
                    coveringFrom: $0.coveringFrom,
                    coveringTo: $0.coveringTo,
                    isOverall: $0.isOverall
                )
            }
    }
}
