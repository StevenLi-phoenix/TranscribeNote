import Foundation

enum LLMEngineFactory {
    /// URLSession shared across all LLM engines: 10-minute timeout to support long-running local models.
    static let llmSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600   // 10 minutes per request
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    static func create(from config: LLMConfig, session: URLSession = llmSession) -> any LLMEngine {
        switch config.provider {
        case .ollama: OllamaEngine(session: session)
        case .openAI: OpenAIEngine(session: session)
        case .anthropic: AnthropicEngine(session: session)
        case .custom: OpenAIEngine(session: session)
        }
    }
}
