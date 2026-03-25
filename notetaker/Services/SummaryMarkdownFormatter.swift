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
        isOverall: Bool
    ) -> String {
        let heading: String
        if isOverall {
            heading = "## Overall Summary"
        } else {
            heading = "## \(coveringFrom.mmss)–\(coveringTo.mmss)"
        }
        return "\(heading)\n\n\(content)"
    }
}
