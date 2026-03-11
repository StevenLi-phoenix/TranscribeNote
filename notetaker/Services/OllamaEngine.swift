import Foundation
import os

nonisolated final class OllamaEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "OllamaEngine")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(prompt: String, config: LLMConfig) async throws -> String {
        let baseURL = LLMHTTPHelpers.normalizeBaseURL(
            config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": config.model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": config.temperature,
                "num_predict": config.maxTokens
            ],
            "think": config.thinkingEnabled
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with Ollama model \(config.model) (thinking: \(config.thinkingEnabled))")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct OllamaResponse: Decodable {
            let response: String
        }

        let ollamaResponse = try LLMHTTPHelpers.decodeResponse(OllamaResponse.self, from: data)
        var content = ollamaResponse.response
        if !config.thinkingEnabled {
            content = LLMHTTPHelpers.stripThinking(from: content)
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LLMEngineError.emptyResponse }

        Self.logger.info("Ollama generation complete (\(result.count) chars)")
        return result
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        let baseURL = LLMHTTPHelpers.normalizeBaseURL(
            config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

}
