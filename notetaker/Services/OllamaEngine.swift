import Foundation
import os

nonisolated final class OllamaEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "OllamaEngine")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Concatenate system and user messages into Ollama's system/prompt fields
        let systemText = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let promptText = messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")

        var body: [String: Any] = [
            "model": config.model,
            "prompt": promptText,
            "stream": false,
            "options": [
                "temperature": config.temperature,
                "num_predict": config.maxTokens
            ],
            "think": config.thinkingEnabled
        ]
        if !systemText.isEmpty {
            body["system"] = systemText
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with Ollama model \(config.model) (thinking: \(config.thinkingEnabled))")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct OllamaResponse: Decodable {
            let response: String
            let prompt_eval_count: Int?
            let eval_count: Int?
        }

        let ollamaResponse = try LLMHTTPHelpers.decodeResponse(OllamaResponse.self, from: data)
        var content = ollamaResponse.response
        if !config.thinkingEnabled {
            content = LLMHTTPHelpers.stripThinking(from: content)
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LLMEngineError.emptyResponse }

        let usage = TokenUsage(
            inputTokens: ollamaResponse.prompt_eval_count ?? 0,
            outputTokens: ollamaResponse.eval_count ?? 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
        Self.logger.info("Ollama usage: input=\(usage.inputTokens) output=\(usage.outputTokens)")

        Self.logger.info("Ollama generation complete (\(result.count) chars)")
        return LLMMessage(role: .assistant, content: result, usage: usage)
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        guard let baseURL = try? LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        ) else { return false }
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

}
