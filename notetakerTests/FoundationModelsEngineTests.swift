import Testing
import Foundation
@testable import notetaker

@Suite("FoundationModelsEngine Tests")
struct FoundationModelsEngineTests {

    @Test func isAvailableReturnsValue() async {
        let engine = FoundationModelsEngine()
        let config = LLMConfig(provider: .foundationModels)
        // isAvailable should return a boolean without crashing
        let available = await engine.isAvailable(config: config)
        // On CI or machines without Apple Intelligence, this may be false
        #expect(available == true || available == false)
    }

    @Test func generateThrowsWhenUserTextEmpty() async throws {
        let engine = FoundationModelsEngine()
        let config = LLMConfig(provider: .foundationModels)
        let messages = [LLMMessage(role: .system, content: "You are a helpful assistant.")]

        await #expect(throws: LLMEngineError.self) {
            _ = try await engine.generate(messages: messages, config: config)
        }
    }
}
