nonisolated final class NoopLLMEngine: LLMEngine, @unchecked Sendable {
    func generate(prompt: String, config: LLMConfig) async throws -> String { "" }
    func isAvailable(config: LLMConfig) async -> Bool { false }
}
