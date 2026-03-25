import Testing
import Foundation
@testable import notetaker

@Suite("LLMEngineFactory Tests", .serialized)
struct LLMEngineFactoryTests {

    @Test func createsFoundationModelsEngine() {
        let config = LLMConfig(provider: .foundationModels)
        let engine = LLMEngineFactory.create(from: config)
        #expect(engine is FoundationModelsEngine)
    }

    @Test func createsOllamaEngine() {
        let config = LLMConfig(provider: .ollama)
        let engine = LLMEngineFactory.create(from: config)
        #expect(engine is OllamaEngine)
    }

    @Test func createsOpenAIEngine() {
        let config = LLMConfig(provider: .openAI)
        let engine = LLMEngineFactory.create(from: config)
        #expect(engine is OpenAIEngine)
    }

    @Test func createsAnthropicEngine() {
        let config = LLMConfig(provider: .anthropic)
        let engine = LLMEngineFactory.create(from: config)
        #expect(engine is AnthropicEngine)
    }

    @Test func customUsesOpenAIEngine() {
        let config = LLMConfig(provider: .custom)
        let engine = LLMEngineFactory.create(from: config)
        #expect(engine is OpenAIEngine)
    }

    @Test func acceptsCustomSession() {
        let sessionConfig = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: sessionConfig)
        let config = LLMConfig(provider: .ollama)
        let engine = LLMEngineFactory.create(from: config, session: session)
        #expect(engine is OllamaEngine)
    }

    @Test func llmSessionHasLongTimeout() {
        let session = LLMEngineFactory.llmSession
        #expect(session.configuration.timeoutIntervalForRequest == 600)
        #expect(session.configuration.timeoutIntervalForResource == 600)
    }
}
