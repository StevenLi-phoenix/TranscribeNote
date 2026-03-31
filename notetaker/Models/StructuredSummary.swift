import Foundation
import FoundationModels

/// Structured summary output with key points, action items, and sentiment.
/// Used by all LLM engines: FoundationModels via `@Generable`, others via JSON Schema.
@Generable
nonisolated struct StructuredSummary: Codable, Sendable, Equatable {
    @Guide(description: "Concise summary of the transcript content, 2-5 sentences")
    var summary: String

    @Guide(description: "List of key points or takeaways")
    var keyPoints: [String]

    @Guide(description: "List of action items or tasks identified")
    var actionItems: [String]

    @Guide(description: "Overall sentiment: positive, neutral, negative, or mixed", .anyOf(["positive", "neutral", "negative", "mixed"]))
    var sentiment: String

    func toJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSON(_ json: String) -> StructuredSummary? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StructuredSummary.self, from: data)
    }
}

/// Provides the JSON Schema for structured summary output (used by OpenAI/Anthropic/Ollama engines).
nonisolated enum SummarySchemaProvider {
    static let schema: JSONSchema = {
        let schemaJSON: [String: Any] = [
            "type": "object",
            "properties": [
                "summary": [
                    "type": "string",
                    "description": "Concise summary of the transcript content, 2-5 sentences"
                ],
                "keyPoints": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "List of key points or takeaways"
                ],
                "actionItems": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "List of action items or tasks identified"
                ],
                "sentiment": [
                    "type": "string",
                    "enum": ["positive", "neutral", "negative", "mixed"],
                    "description": "Overall sentiment: positive, neutral, negative, or mixed"
                ]
            ],
            "required": ["summary", "keyPoints", "actionItems", "sentiment"],
            "additionalProperties": false
        ]
        // Force-unwrap is safe: schema is a compile-time constant
        let data = try! JSONSerialization.data(withJSONObject: schemaJSON)
        return JSONSchema(
            name: "structured_summary",
            description: "A structured summary with key points, action items, and sentiment analysis",
            schemaData: data,
            strict: true
        )
    }()
}
