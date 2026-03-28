import Foundation

/// Parses LLM tag responses into normalized tag arrays.
/// Uses deterministic hashing for consistent color assignment across app launches.
nonisolated enum TagParser {
    /// Parse tags from LLM response text.
    /// Handles: JSON arrays, comma-separated, newline-separated.
    static func parse(from response: String) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try JSON array first
        if let jsonTags = parseJSON(trimmed) {
            return normalize(jsonTags)
        }

        // Try comma-separated
        if trimmed.contains(",") {
            let tags = trimmed.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]"))
            }
            return normalize(tags)
        }

        // Try newline-separated
        let tags = trimmed.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "- \u{2022}\"'"))
        }
        return normalize(tags)
    }

    private static func parseJSON(_ text: String) -> [String]? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return nil }
        let jsonStr = String(text[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return nil }
        return array
    }

    private static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 20 }
            .prefix(5)
            .filter { seen.insert($0.lowercased()).inserted }
            .map { String($0) }
    }

    /// Deterministic color index for a tag using djb2 hash.
    /// Unlike `String.hashValue`, this produces the same result across app launches.
    static func colorIndex(for tag: String) -> Int {
        let hash = djb2Hash(tag.lowercased())
        return Int(hash % 8)
    }

    /// djb2 hash algorithm — deterministic, fast, well-distributed for short strings.
    private static func djb2Hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }
}
