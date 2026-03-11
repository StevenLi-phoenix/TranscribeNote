import Foundation
import os

nonisolated final class AnthropicEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "AnthropicEngine")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(prompt: String, config: LLMConfig) async throws -> String {
        let raw = config.baseURL.isEmpty ? "https://api.anthropic.com" : config.baseURL
        let root = LLMHTTPHelpers.normalizeBaseURL(raw, stripV1: true)
        guard let url = URL(string: "\(root)/v1/messages") else {
            throw LLMEngineError.invalidURL(root)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard !config.apiKey.isEmpty else {
            throw LLMEngineError.notConfigured
        }
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with Anthropic model \(config.model)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        struct AnthropicResponse: Decodable {
            let content: [ContentBlock]
        }

        let anthropicResponse = try LLMHTTPHelpers.decodeResponse(AnthropicResponse.self, from: data)
        guard var text = anthropicResponse.content.first(where: { $0.type == "text" })?.text else {
            throw LLMEngineError.emptyResponse
        }
        if !config.thinkingEnabled {
            text = LLMHTTPHelpers.stripThinking(from: text)
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LLMEngineError.emptyResponse }

        Self.logger.info("Anthropic generation complete (\(result.count) chars)")
        return result
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        !config.apiKey.isEmpty
    }

}
