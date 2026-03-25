import Foundation
import os

enum LLMEngineFactory {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMEngineFactory")

    /// URLSession shared across all LLM engines: 10-minute timeout to support long-running local models.
    static let llmSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600   // 10 minutes per request
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    static func create(from config: LLMConfig, session: URLSession = llmSession) -> any LLMEngine {
        switch config.provider {
        case .foundationModels: FoundationModelsEngine()
        case .ollama: OllamaEngine(session: session)
        case .openAI: OpenAIEngine(session: session)
        case .anthropic: AnthropicEngine(session: session)
        case .custom: OpenAIEngine(session: session)
        }
    }

    /// Create an engine with automatic fallback to Foundation Models when the primary is unavailable.
    static func createWithFallback(from config: LLMConfig, session: URLSession = llmSession) async -> any LLMEngine {
        if config.provider == .foundationModels {
            return FoundationModelsEngine()
        }
        let engine = create(from: config, session: session)
        if await engine.isAvailable(config: config) {
            return engine
        }
        // Try Foundation Models as fallback
        if FoundationModelsEngine.isModelAvailable {
            logger.info("Primary engine (\(config.provider.rawValue)) unavailable, falling back to Foundation Models")
            return FoundationModelsEngine()
        }
        // Neither available — return primary, will fail at generate time with a clear error
        logger.warning("Both primary engine and Foundation Models unavailable")
        return engine
    }
}
