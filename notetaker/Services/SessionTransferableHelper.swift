import SwiftUI
import UniformTypeIdentifiers
import os

/// Lightweight value type carrying session data for export — no SwiftData dependency.
nonisolated struct SessionExportInfo: Sendable {
    let title: String
    let startedAt: Date
    let segments: [(startTime: TimeInterval, text: String)]
    let summaryContent: String?

    /// Format session as plain text with timestamped transcript.
    func formatAsPlainText() -> String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append(startedAt.formatted(date: .abbreviated, time: .shortened))
        lines.append("")

        if let summaryContent, !summaryContent.isEmpty {
            lines.append("## Summary")
            lines.append(summaryContent)
            lines.append("")
        }

        if !segments.isEmpty {
            lines.append("## Transcript")
            for segment in segments {
                let time = formatTime(segment.startTime)
                lines.append("\(time)  \(segment.text)")
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

    /// Sanitize title for use as filename.
    func sanitizedFilename() -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let limited = String(cleaned.prefix(80))
        return limited.isEmpty ? "session" : limited
    }
}

/// Transferable wrapper for dragging sessions out of the app.
///
/// Since `RecordingSession` is a SwiftData `@Model` (reference type with MainActor isolation),
/// we snapshot data into `SessionExportInfo` and wrap it here for `Transferable` conformance.
struct SessionExportItem: Transferable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "SessionExportItem"
    )

    let info: SessionExportInfo

    static var transferRepresentation: some TransferRepresentation {
        // Plain text — drag to text fields, editors, etc.
        DataRepresentation(exportedContentType: .plainText) { item in
            Self.logger.info("Exporting plain text for session: \(item.info.title)")
            let text = item.info.formatAsPlainText()
            return Data(text.utf8)
        }

        // Text file — drag to Finder, file-accepting apps
        FileRepresentation(exportedContentType: .utf8PlainText) { item in
            let text = item.info.formatAsPlainText()
            let filename = item.info.sanitizedFilename() + ".txt"
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(filename)
            try Data(text.utf8).write(to: tempURL)
            Self.logger.info("Exported text file to: \(tempURL.path)")
            return SentTransferredFile(tempURL)
        }
    }
}

// MARK: - Convenience initializer from RecordingSession

extension SessionExportItem {
    /// Create from a RecordingSession (must be called on MainActor).
    @MainActor
    init(session: RecordingSession) {
        let sortedSegments = session.segments
            .sorted { $0.startTime < $1.startTime }
            .map { (startTime: $0.startTime, text: $0.text) }

        let overallSummary = session.summaries
            .filter(\.isOverall)
            .first?
            .displayContent

        self.info = SessionExportInfo(
            title: session.title,
            startedAt: session.startedAt,
            segments: sortedSegments,
            summaryContent: overallSummary
        )
    }
}
