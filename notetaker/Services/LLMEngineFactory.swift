import Foundation

enum LLMEngineFactory {
    static func create(from config: LLMConfig, session: URLSession = .shared) -> any LLMEngine {
        switch config.provider {
        case .ollama: OllamaEngine(session: session)
        case .openAI: OpenAIEngine(session: session)
        case .anthropic: AnthropicEngine(session: session)
        case .custom: OpenAIEngine(session: session)
        }
    }
}
