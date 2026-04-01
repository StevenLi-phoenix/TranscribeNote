import Testing
import Foundation
@testable import TranscribeNote

@Suite("LLMEngineFactory Fallback Tests", .serialized)
struct LLMEngineFactoryFallbackTests {

    @Test func fallbackReturnsFoundationModelsDirectly() async {
        let config = LLMConfig(provider: .foundationModels)
        let engine = await LLMEngineFactory.createWithFallback(from: config)
        #expect(engine is FoundationModelsEngine)
    }

    @Test func fallbackReturnsOllamaWhenAvailable() async {
        // Ollama is likely not running in test, so this tests the fallback path
        let config = LLMConfig(provider: .ollama, model: "test", baseURL: "http://localhost:11434")
        let engine = await LLMEngineFactory.createWithFallback(from: config)
        // Either Ollama (if running) or FoundationModels (if available) or Ollama (neither available)
        #expect(engine is OllamaEngine || engine is FoundationModelsEngine)
    }

    @Test func defaultConfigUsesFoundationModels() {
        let config = LLMConfig.default
        #expect(config.provider == .foundationModels)
    }

    @Test func defaultInitUsesFoundationModels() {
        let config = LLMConfig()
        #expect(config.provider == .foundationModels)
    }
}
