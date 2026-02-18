nonisolated enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case ollama
    case openAI
    case anthropic
    case custom
}
