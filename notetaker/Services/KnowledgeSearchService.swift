import Foundation
import SwiftData
import os

// MARK: - Data Types

/// A single matched snippet from cross-session search.
nonisolated struct SearchSnippet: Identifiable, Sendable {
    let id: UUID
    let sessionID: PersistentIdentifier
    let sessionTitle: String
    let sessionDate: Date
    let segmentText: String
    let segmentStartTime: TimeInterval
    let score: Double

    init(
        id: UUID = UUID(),
        sessionID: PersistentIdentifier,
        sessionTitle: String,
        sessionDate: Date,
        segmentText: String,
        segmentStartTime: TimeInterval,
        score: Double
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.sessionDate = sessionDate
        self.segmentText = segmentText
        self.segmentStartTime = segmentStartTime
        self.score = score
    }
}

/// Search snippets grouped by session, sorted by top score.
nonisolated struct SessionSearchGroup: Identifiable, Sendable {
    let id: PersistentIdentifier
    let sessionTitle: String
    let sessionDate: Date
    let snippets: [SearchSnippet]
    var topScore: Double { snippets.map(\.score).max() ?? 0 }
}

// MARK: - Pure Logic (nonisolated, testable)

/// Pure-logic helpers for cross-session knowledge search.
/// Extracted as nonisolated for testability without MainActor.
nonisolated enum KnowledgeSearchLogic {

    // MARK: - Stopwords

    /// Common English and Chinese stopwords to strip from queries.
    static let stopwords: Set<String> = [
        // English
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "need", "dare", "ought",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "as",
        "into", "through", "during", "before", "after", "above", "below",
        "between", "out", "off", "over", "under", "again", "further", "then",
        "once", "and", "but", "or", "nor", "not", "so", "yet", "both",
        "each", "few", "more", "most", "other", "some", "such", "no",
        "only", "own", "same", "than", "too", "very", "just", "because",
        "about", "if", "when", "where", "what", "which", "who", "whom",
        "this", "that", "these", "those", "i", "me", "my", "we", "our",
        "you", "your", "he", "him", "his", "she", "her", "it", "its",
        "they", "them", "their", "how", "all", "any", "up",
        // Chinese
        "的", "了", "是", "在", "我", "有", "和", "就", "不", "人",
        "都", "一", "一个", "上", "也", "很", "到", "说", "要", "去",
        "你", "会", "着", "没有", "看", "好", "自己", "这", "他", "她",
        "吗", "呢", "吧", "啊", "呀", "哦", "嗯",
    ]

    /// Extract search keywords from a natural language query.
    /// Strips common stopwords, lowercases, deduplicates, preserves order.
    static func extractKeywords(from query: String) -> [String] {
        // Split on whitespace and common punctuation
        let tokens = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics
                .union(.init(charactersIn: "\u{4E00}"..."\u{9FFF}"))  // CJK range
                .union(.init(charactersIn: "\u{3400}"..."\u{4DBF}"))  // CJK Extension A
                .inverted)
            .filter { !$0.isEmpty }

        // Also split CJK text into individual characters for single-char matching
        var expanded: [String] = []
        for token in tokens {
            if token.unicodeScalars.allSatisfy({ isCJK($0) }) && token.count > 1 {
                // Add whole token and individual characters
                expanded.append(token)
                for char in token {
                    expanded.append(String(char))
                }
            } else {
                expanded.append(token)
            }
        }

        // Remove stopwords and deduplicate preserving order
        var seen = Set<String>()
        return expanded.filter { token in
            guard !stopwords.contains(token), seen.insert(token).inserted else { return false }
            return true
        }
    }

    /// Check if a unicode scalar is in CJK range.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    /// Score a snippet's relevance given keywords.
    /// Score = matchCount * 2.0 + recencyBonus
    /// recencyBonus: 1.0 if within 7 days, 0.5 if within 30 days, 0.2 otherwise.
    static func relevanceScore(text: String, keywords: [String], date: Date, now: Date = Date()) -> Double {
        guard !keywords.isEmpty else { return 0 }

        let lowered = text.lowercased()
        let matchCount = keywords.filter { lowered.contains($0) }.count

        guard matchCount > 0 else { return 0 }

        let daysSince = now.timeIntervalSince(date) / 86400.0
        let recencyBonus: Double
        if daysSince <= 7 {
            recencyBonus = 1.0
        } else if daysSince <= 30 {
            recencyBonus = 0.5
        } else {
            recencyBonus = 0.2
        }

        return Double(matchCount) * 2.0 + recencyBonus
    }

    /// Group and sort search snippets by session, deduplicating overlapping segments.
    /// Groups sorted by topScore descending. Snippets within each group sorted by startTime.
    static func groupBySession(_ snippets: [SearchSnippet]) -> [SessionSearchGroup] {
        let grouped = Dictionary(grouping: snippets) { $0.sessionID }

        return grouped.map { (sessionID, sessionSnippets) in
            // Deduplicate by segmentText (keep highest scored)
            var seen = Set<String>()
            let deduped = sessionSnippets
                .sorted { $0.score > $1.score }
                .filter { seen.insert($0.segmentText).inserted }
                .sorted { $0.segmentStartTime < $1.segmentStartTime }

            let first = deduped[0]
            return SessionSearchGroup(
                id: sessionID,
                sessionTitle: first.sessionTitle,
                sessionDate: first.sessionDate,
                snippets: deduped
            )
        }
        .sorted { $0.topScore > $1.topScore }
    }

    /// Format search results into context string for LLM prompt.
    /// Truncates to maxChars to fit within LLM context window.
    static func formatContext(groups: [SessionSearchGroup], maxChars: Int = 8000) -> String {
        guard !groups.isEmpty else { return "" }

        var result = ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for group in groups {
            let header = "## \(group.sessionTitle) (\(dateFormatter.string(from: group.sessionDate)))\n"

            if result.count + header.count > maxChars { break }
            result += header

            for snippet in group.snippets {
                let line = "[\(snippet.segmentStartTime.mmss)] \(snippet.segmentText)\n"
                if result.count + line.count > maxChars { break }
                result += line
            }
            result += "\n"
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Uses TimeInterval.mmss from Extensions/TimeInterval+Formatting.swift
