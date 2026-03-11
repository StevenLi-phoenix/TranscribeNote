import Foundation
import os

nonisolated final class OpenAIEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "OpenAIEngine")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(prompt: String, config: LLMConfig) async throws -> String {
        let baseURL = LLMHTTPHelpers.normalizeBaseURL(
            config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]
        // Pass enable_thinking for OpenAI-compatible servers (LM Studio, vLLM, etc.)
        body["chat_template_kwargs"] = ["enable_thinking": config.thinkingEnabled]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with OpenAI model \(config.model) (thinking: \(config.thinkingEnabled))")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        struct OpenAIResponse: Decodable {
            let choices: [Choice]
        }

        let openAIResponse = try LLMHTTPHelpers.decodeResponse(OpenAIResponse.self, from: data)
        guard var content = openAIResponse.choices.first?.message.content else {
            throw LLMEngineError.emptyResponse
        }
        // Fallback: strip <think> blocks if server didn't honor the parameter
        if !config.thinkingEnabled {
            content = LLMHTTPHelpers.stripThinking(from: content)
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LLMEngineError.emptyResponse }

        Self.logger.info("OpenAI generation complete (\(result.count) chars)")
        return result
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        let baseURL = LLMHTTPHelpers.normalizeBaseURL(
            config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/models") else { return false }
        do {
            var request = URLRequest(url: url)
            if !config.apiKey.isEmpty {
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            }
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

}
