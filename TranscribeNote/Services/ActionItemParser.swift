import Foundation
import os

/// Parses LLM output into structured action items with robust fallback handling.
enum ActionItemParser {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TranscribeNote", category: "ActionItemParser")

    /// Raw parsed action item before conversion to SwiftData model.
    struct RawActionItem: Decodable, Sendable {
        let content: String
        let category: String
        let assignee: String?
        let dueDate: String?  // "YYYY-MM-DD" format
    }

    /// JSON Schema for structured output (used by engines that support it).
    static var jsonSchema: JSONSchema? {
        let schema = """
        {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "content": { "type": "string", "description": "Description of the action item" },
              "category": { "type": "string", "enum": ["task", "decision", "followUp"] },
              "assignee": { "type": ["string", "null"], "description": "Person responsible, or null" },
              "dueDate": { "type": ["string", "null"], "description": "Due date in YYYY-MM-DD format, or null" }
            },
            "required": ["content", "category"],
            "additionalProperties": false
          }
        }
        """
        guard let data = schema.data(using: .utf8) else { return nil }
        return JSONSchema(
            name: "action_items",
            description: "Array of action items extracted from a transcript",
            schemaData: data,
            strict: true
        )
    }

    /// Parse LLM output into action items. Tries JSON first, falls back to markdown checklist.
    static func parse(_ rawOutput: String) -> [RawActionItem] {
        let cleaned = stripNoise(rawOutput)

        // Try JSON parsing first
        if let items = parseJSON(cleaned), !items.isEmpty {
            logger.info("Parsed \(items.count) action items from JSON")
            return items
        }

        // Fallback: parse markdown checklist
        let items = parseMarkdownChecklist(rawOutput)
        if !items.isEmpty {
            logger.info("Parsed \(items.count) action items from markdown fallback")
        } else {
            logger.warning("No action items parsed from LLM output (\(rawOutput.count) chars)")
        }
        return items
    }

    /// Strip common LLM noise: thinking blocks, code fences, preamble.
    private static func stripNoise(_ input: String) -> String {
        var result = input

        // Strip <think>...</think> blocks
        result = result.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )

        // Strip markdown code fences
        if let match = result.range(of: #"```(?:json)?\s*([\s\S]*?)\s*```"#, options: .regularExpression) {
            // Extract content inside fences
            let fenced = String(result[match])
            let inner = fenced
                .replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            result = inner
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Try to parse as JSON array of action items.
    private static func parseJSON(_ input: String) -> [RawActionItem]? {
        // Find the JSON array boundaries
        guard let startIndex = input.firstIndex(of: "["),
              let endIndex = input.lastIndex(of: "]") else {
            return nil
        }

        let jsonString = String(input[startIndex...endIndex])
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let decoder = JSONDecoder()
            let items = try decoder.decode([RawActionItem].self, from: data)
            return items.filter { !$0.content.isEmpty }
        } catch {
            logger.warning("JSON decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fallback: parse markdown checklist lines like `- [ ] Do something`.
    private static func parseMarkdownChecklist(_ input: String) -> [RawActionItem] {
        let pattern = #"^[-*]\s*\[[ x]\]\s*(.+)$"#
        let lines = input.components(separatedBy: .newlines)

        return lines.compactMap { line -> RawActionItem? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let range = trimmed.range(of: pattern, options: .regularExpression) else {
                return nil
            }
            _ = range // suppress unused warning — we just need the match confirmation

            // Extract content after the checkbox
            let content = trimmed
                .replacingOccurrences(of: #"^[-*]\s*\[[ x]\]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else { return nil }

            return RawActionItem(content: content, category: "task", assignee: nil, dueDate: nil)
        }
    }

    /// Parse a date string in YYYY-MM-DD format to Date.
    static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
}
