import Foundation
import os

/// Word counting and metrics formatting for summary content.
nonisolated enum WordCounter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "WordCounter")

    /// Count words in text, handling both CJK and Latin scripts.
    static func count(in text: String) -> Int {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return 0 }

        if isCJKDominant(cleaned) {
            // CJK-dominant: count meaningful characters (no whitespace, no punctuation)
            let count = cleaned.filter { !$0.isWhitespace && !$0.isPunctuation }.count
            logger.debug("CJK word count: \(count) chars")
            return count
        } else {
            // Latin-dominant: count words by whitespace splitting
            let count = cleaned.split(whereSeparator: { $0.isWhitespace }).count
            logger.debug("Latin word count: \(count) words")
            return count
        }
    }

    /// Format word count and duration into a compact display string.
    /// - Parameters:
    ///   - wordCount: Number of words
    ///   - duration: Duration in seconds (coveringTo - coveringFrom)
    ///   - isCJK: Whether the text is CJK-dominant
    /// - Returns: Formatted string like "~320 words · 5 min" or "~150 字 · 3 min"
    static func formatMetrics(wordCount: Int, duration: TimeInterval, isCJK: Bool = false) -> String {
        let wordLabel = isCJK ? "字" : (wordCount == 1 ? "word" : "words")
        let durationStr: String
        if duration < 60 {
            durationStr = "\(Int(duration))s"
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            if seconds == 0 {
                durationStr = "\(minutes) min"
            } else {
                durationStr = "\(minutes)m \(seconds)s"
            }
        }
        return "~\(wordCount) \(wordLabel) · \(durationStr)"
    }

    /// Format word count only (no duration), for overall summaries.
    static func formatWordCount(wordCount: Int, isCJK: Bool = false) -> String {
        let wordLabel = isCJK ? "字" : (wordCount == 1 ? "word" : "words")
        return "~\(wordCount) \(wordLabel)"
    }

    /// Detect if text is primarily CJK.
    static func isCJKDominant(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let cjkCount = cleaned.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains($0.value) ||
            (0x3400...0x4DBF).contains($0.value)
        }.count
        let totalNonSpace = cleaned.filter { !$0.isWhitespace }.count
        return totalNonSpace > 0 && Double(cjkCount) / Double(totalNonSpace) > 0.3
    }
}
