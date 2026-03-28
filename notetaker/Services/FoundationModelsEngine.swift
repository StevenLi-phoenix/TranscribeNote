import Foundation
import FoundationModels
import os

nonisolated final class FoundationModelsEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "FoundationModelsEngine")

    /// Injected closure providing session data for the related-sessions search tool.
    var sessionProvider: (@Sendable () async -> [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])])?

    /// Injected closure providing calendar event data for the calendar lookup tool.
    var calendarProvider: (@Sendable () async -> (title: String?, attendees: [String], location: String?, notes: String?))?

    /// Check whether Foundation Models is available on this device.
    /// Returns false (never crashes) when Apple Intelligence is not enabled or unsupported.
    static var isModelAvailable: Bool {
        guard let availability = try? SystemLanguageModel.default.availability else {
            return false
        }
        return availability == .available
    }

    /// Tool calling is supported when the user has enabled the setting and providers are configured.
    var supportsToolCalling: Bool {
        UserDefaults.standard.bool(forKey: "fmToolCallingEnabled")
            && (sessionProvider != nil || calendarProvider != nil)
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

    func generateWithTools(messages: [LLMMessage], tools: [LLMTool], config: LLMConfig) async throws -> LLMToolResponse {
        guard Self.isModelAvailable else {
            Self.logger.error("Foundation Models not available for tool calling")
            throw LLMEngineError.notConfigured
        }

        let systemText = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let userText = messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")

        guard !userText.isEmpty else {
            throw LLMEngineError.emptyResponse
        }

        Self.logger.info("Generating with Foundation Models + tools (prompt: \(userText.count) chars)")

        do {
            let content = try await generateWithNativeTools(systemText: systemText, userText: userText)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw LLMEngineError.emptyResponse }

            Self.logger.info("Foundation Models tool-assisted generation complete (\(trimmed.count) chars)")
            return .text(LLMMessage(role: .assistant, content: trimmed, usage: .zero))
        } catch let error as LLMEngineError {
            throw error
        } catch {
            Self.logger.error("Foundation Models tool calling failed: \(error.localizedDescription)")
            throw LLMEngineError.networkError(error)
        }
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        Self.isModelAvailable
    }

    // MARK: - Private

    /// Create a LanguageModelSession with native FM tools and generate a response.
    /// The session handles the tool calling loop automatically.
    private func generateWithNativeTools(systemText: String, userText: String) async throws -> String {
        var nativeTools: [any Tool] = []

        if let sessionProvider {
            nativeTools.append(RelatedSessionSearchTool(sessionProvider: sessionProvider))
            Self.logger.debug("Registered RelatedSessionSearchTool")
        }
        if let calendarProvider {
            nativeTools.append(CalendarEventLookupTool(calendarProvider: calendarProvider))
            Self.logger.debug("Registered CalendarEventLookupTool")
        }

        Self.logger.info("Creating FM session with \(nativeTools.count) native tool(s)")

        let session: LanguageModelSession
        if systemText.isEmpty {
            session = LanguageModelSession(tools: nativeTools)
        } else {
            session = LanguageModelSession(tools: nativeTools) { systemText }
        }

        let response = try await session.respond(to: userText)
        return response.content
    }
}
