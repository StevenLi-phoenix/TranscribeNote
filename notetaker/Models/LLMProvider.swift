nonisolated enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case ollama
    case openAI
    case anthropic
    case custom

    /// Default base URL for each provider (without trailing path components like /v1).
    var defaultBaseURL: String {
        switch self {
        case .ollama: "http://localhost:11434"
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .custom: "http://localhost:1234/v1"
        }
    }
}
