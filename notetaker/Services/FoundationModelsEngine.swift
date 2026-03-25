import Foundation
import FoundationModels
import os

nonisolated final class FoundationModelsEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "FoundationModelsEngine")

    /// Check whether Foundation Models is available on this device.
    /// Returns false (never crashes) when Apple Intelligence is not enabled or unsupported.
    static var isModelAvailable: Bool {
        guard let availability = try? SystemLanguageModel.default.availability else {
            return false
        }
        return availability == .available
    }

    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage {
        guard Self.isModelAvailable else {
            Self.logger.error("Foundation Models not available — Apple Intelligence may not be enabled")
            throw LLMEngineError.notConfigured
        }

        // Extract system instructions and user prompt from messages
        let systemText = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let userText = messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")

        guard !userText.isEmpty else {
            throw LLMEngineError.emptyResponse
        }

        let session: LanguageModelSession
        if systemText.isEmpty {
            session = LanguageModelSession()
        } else {
            session = LanguageModelSession(instructions: systemText)
        }

        Self.logger.info("Generating with Foundation Models (prompt: \(userText.count) chars)")

        do {
            let response = try await session.respond(to: userText)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { throw LLMEngineError.emptyResponse }

            Self.logger.info("Foundation Models generation complete (\(content.count) chars)")
            return LLMMessage(role: .assistant, content: content, usage: .zero)
        } catch let error as LLMEngineError {
            throw error
        } catch {
            Self.logger.error("Foundation Models generation failed: \(error.localizedDescription)")
            throw LLMEngineError.networkError(error)
        }
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        Self.isModelAvailable
    }
}
