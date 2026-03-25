nonisolated enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case foundationModels
    case ollama
    case openAI
    case anthropic
    case custom

    /// Default base URL for each provider (without trailing path components like /v1).
    var defaultBaseURL: String {
        switch self {
        case .foundationModels: ""
        case .ollama: "http://localhost:11434"
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .custom: "http://localhost:1234/v1"
        }
    }

    /// Human-readable display name for the settings UI.
    var displayName: String {
        switch self {
        case .foundationModels: "Apple Intelligence (On-Device)"
        case .ollama: "Ollama"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }
}
