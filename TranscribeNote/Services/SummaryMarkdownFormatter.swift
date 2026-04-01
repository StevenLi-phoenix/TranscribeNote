import Foundation

enum SummaryMarkdownFormatter {
    /// Formats summary content as Markdown with appropriate heading.
    /// - Parameters:
    ///   - content: The summary text (use `displayContent` for edited summaries).
    ///   - coveringFrom: Start time in seconds.
    ///   - coveringTo: End time in seconds.
    ///   - isOverall: Whether this is an overall summary.
    /// - Returns: Markdown-formatted string.
    static func format(
        content: String,
        coveringFrom: TimeInterval,
        coveringTo: TimeInterval,
        isOverall: Bool,
        structuredSummary: StructuredSummary? = nil
    ) -> String {
        let heading: String
        if isOverall {
            heading = "## Overall Summary"
        } else {
            heading = "## \(coveringFrom.mmss)–\(coveringTo.mmss)"
        }

        guard let structured = structuredSummary else {
            return "\(heading)\n\n\(content)"
        }

        var parts = ["\(heading)\n\n\(structured.summary)"]

        if !structured.keyPoints.isEmpty {
            let points = structured.keyPoints.map { "- \($0)" }.joined(separator: "\n")
            parts.append("### Key Points\n\n\(points)")
        }

        if !structured.actionItems.isEmpty {
            let items = structured.actionItems.map { "- [ ] \($0)" }.joined(separator: "\n")
            parts.append("### Action Items\n\n\(items)")
        }

        parts.append("**Sentiment:** \(structured.sentiment)")

        return parts.joined(separator: "\n\n")
    }
}
