nonisolated final class NoopLLMEngine: LLMEngine, @unchecked Sendable {
    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage {
        LLMMessage(role: .assistant, content: "", usage: .zero)
    }
    func isAvailable(config: LLMConfig) async -> Bool { false }
}
