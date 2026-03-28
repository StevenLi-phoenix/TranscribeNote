import Foundation
import os

nonisolated enum MarkdownExporter {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "MarkdownExporter"
    )

    // MARK: - Data types

    struct ExportOptions: Sendable {
        var includeYAMLFrontmatter: Bool = true
        var includeSummary: Bool = true
        var includeTranscript: Bool = true
        var transcriptFormat: TranscriptFormat = .timestamped
        var customTags: [String] = []
    }

    enum TranscriptFormat: Sendable {
        case table
        case timestamped
    }

    struct SummaryInfo: Sendable {
        let content: String
        let coveringFrom: TimeInterval
        let coveringTo: TimeInterval
        let isOverall: Bool
    }

    struct SegmentInfo: Sendable {
        let startTime: TimeInterval
        let text: String
    }

    // MARK: - Export

    static func export(
        title: String,
        date: Date,
        totalDuration: TimeInterval,
        segments: [SegmentInfo],
        summaries: [SummaryInfo],
        options: ExportOptions
    ) -> String {
        logger.info("Exporting Markdown: title=\(title), segments=\(segments.count), summaries=\(summaries.count)")
        var parts: [String] = []

        if options.includeYAMLFrontmatter {
            parts.append(generateFrontmatter(
                title: title,
                date: date,
                totalDuration: totalDuration,
                segmentsCount: segments.count,
                tags: options.customTags
            ))
        }

        if options.includeSummary {
            let summarySection = formatSummaries(summaries)
            if !summarySection.isEmpty {
                parts.append("# Summary\n\n\(summarySection)")
            }
        }

        if options.includeTranscript && !segments.isEmpty {
            let transcriptSection = formatTranscript(segments, format: options.transcriptFormat)
            parts.append("# Transcript\n\n\(transcriptSection)")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Frontmatter

    static func generateFrontmatter(
        title: String,
        date: Date,
        totalDuration: TimeInterval,
        segmentsCount: Int,
        tags: [String]
    ) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        let dateString = iso8601.string(from: date)
        let durationString = totalDuration.hhmmss

        var lines: [String] = [
            "---",
            "title: \"\(escapedTitle)\"",
            "date: \(dateString)",
            "duration: \"\(durationString)\"",
            "duration_seconds: \(Int(totalDuration))",
            "type: meeting-note",
            "source: notetaker",
        ]

        if !tags.isEmpty {
            lines.append("tags:")
            for tag in tags {
                lines.append("  - \(tag)")
            }
        }

        lines.append("segments_count: \(segmentsCount)")
        lines.append("---")

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Summaries

    static func formatSummaries(_ summaries: [SummaryInfo]) -> String {
        guard !summaries.isEmpty else { return "" }

        var parts: [String] = []

        // Overall summaries first
        let overalls = summaries.filter(\.isOverall)
        for summary in overalls {
            parts.append("## Overall Summary\n\n\(summary.content)")
        }

        // Chunk summaries sorted by time
        let chunks = summaries
            .filter { !$0.isOverall }
            .sorted { $0.coveringFrom < $1.coveringFrom }
        for chunk in chunks {
            let from = chunk.coveringFrom.mmss
            let to = chunk.coveringTo.mmss
            parts.append("## \(from)–\(to)\n\n\(chunk.content)")
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Transcript

    static func formatTranscript(
        _ segments: [SegmentInfo],
        format: TranscriptFormat
    ) -> String {
        switch format {
        case .timestamped:
            return segments
                .map { "[\($0.startTime.mmss)] \($0.text)" }
                .joined(separator: "\n")

        case .table:
            var lines = [
                "| Time | Content |",
                "|------|---------|",
            ]
            for segment in segments {
                lines.append("| \(segment.startTime.mmss) | \(segment.text) |")
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Filename

    static func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let sanitized = name.unicodeScalars
            .filter { !illegal.contains($0) }
            .map { String($0) }
            .joined()
        return sanitized.isEmpty ? "untitled" : sanitized
    }
}
