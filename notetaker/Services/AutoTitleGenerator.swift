import Foundation
import os

/// Generates a short auto-title from the first transcript text.
/// Extracted as nonisolated enum for testability.
nonisolated enum AutoTitleGenerator {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "AutoTitleGenerator")

    /// Filler words to strip before generating title
    private static let fillerWords: Set<String> = [
        "um", "uh", "er", "ah", "like", "you know", "so", "well",
        "嗯", "啊", "那个", "就是", "然后", "对", "哦"
    ]

    /// Generate a title from transcript text.
    /// Returns nil if text is too short or only filler words.
    static func generate(from text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let isCJK = cleaned.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) ||
            (0x3400...0x4DBF).contains($0.value)
        }

        if isCJK {
            return generateCJKTitle(from: cleaned)
        } else {
            return generateLatinTitle(from: cleaned)
        }
    }

    private static func generateCJKTitle(from text: String) -> String? {
        // Filter filler: remove known filler substrings from start
        var t = text
        for filler in fillerWords {
            while t.hasPrefix(filler) {
                t = String(t.dropFirst(filler.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard t.count >= 3 else { return nil }

        let maxLen = 20
        if t.count <= maxLen {
            return t
        }
        return String(t.prefix(maxLen)) + "…"
    }

    private static func generateLatinTitle(from text: String) -> String? {
        let words = text.split(separator: " ").map(String.init)
        // Filter filler words (case-insensitive)
        let meaningful = words.filter { !fillerWords.contains($0.lowercased()) }
        guard meaningful.count >= 2 else { return nil }

        let maxWords = 8
        let selected = Array(meaningful.prefix(maxWords))
        let title = selected.joined(separator: " ")

        if meaningful.count > maxWords {
            return title + "…"
        }
        return title
    }

    /// Check if a title is a default auto-generated title (not user-edited).
    static func isDefaultTitle(_ title: String) -> Bool {
        // Default format: "Recording Mar 24, 2026, 2:30 PM" or similar locale variations
        title.hasPrefix("Recording ")
    }
}
