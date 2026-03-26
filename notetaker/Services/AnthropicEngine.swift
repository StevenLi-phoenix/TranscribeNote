import Foundation
import os

nonisolated final class AnthropicEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "AnthropicEngine")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage {
        let raw = config.baseURL.isEmpty ? "https://api.anthropic.com" : config.baseURL
        let root = try LLMHTTPHelpers.validateBaseURL(raw, stripV1: true)
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
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

        // Build system parameter from system messages
        let systemMessages = messages.filter { $0.role == .system }
        let userMessages = messages.filter { $0.role != .system }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
        ]

        // System: array of content blocks with optional cache_control
        if !systemMessages.isEmpty {
            let systemBlocks: [[String: Any]] = systemMessages.map { msg in
                var block: [String: Any] = ["type": "text", "text": msg.content]
                if msg.cacheHint {
                    block["cache_control"] = ["type": "ephemeral"]
                }
                return block
            }
            body["system"] = systemBlocks
        }

        // Messages: user/assistant messages with optional cache_control
        let apiMessages: [[String: Any]] = userMessages.map { msg in
            var msgDict: [String: Any] = ["role": msg.role.rawValue]
            if msg.cacheHint {
                msgDict["content"] = [
                    ["type": "text", "text": msg.content, "cache_control": ["type": "ephemeral"]]
                ]
            } else {
                msgDict["content"] = msg.content
            }
            return msgDict
        }
        body["messages"] = apiMessages

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with Anthropic model \(config.model)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
        struct AnthropicResponse: Decodable {
            let content: [ContentBlock]
            let usage: Usage?
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

        let usage: TokenUsage
        if let u = anthropicResponse.usage {
            usage = TokenUsage(
                inputTokens: u.input_tokens ?? 0,
                outputTokens: u.output_tokens ?? 0,
                cacheCreationTokens: u.cache_creation_input_tokens ?? 0,
                cacheReadTokens: u.cache_read_input_tokens ?? 0
            )
            Self.logger.info("Anthropic usage: input=\(usage.inputTokens) output=\(usage.outputTokens) cache_create=\(usage.cacheCreationTokens) cache_read=\(usage.cacheReadTokens)")
        } else {
            usage = .zero
        }

        Self.logger.info("Anthropic generation complete (\(result.count) chars)")
        return LLMMessage(role: .assistant, content: result, usage: usage)
    }

    var supportsStructuredOutput: Bool { true }

    func generateStructured(messages: [LLMMessage], schema: JSONSchema, config: LLMConfig) async throws -> StructuredOutput {
        let raw = config.baseURL.isEmpty ? "https://api.anthropic.com" : config.baseURL
        let root = try LLMHTTPHelpers.validateBaseURL(raw, stripV1: true)
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
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

        // Build system parameter from system messages
        let systemMessages = messages.filter { $0.role == .system }
        let userMessages = messages.filter { $0.role != .system }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
        ]

        // System: array of content blocks with optional cache_control
        if !systemMessages.isEmpty {
            let systemBlocks: [[String: Any]] = systemMessages.map { msg in
                var block: [String: Any] = ["type": "text", "text": msg.content]
                if msg.cacheHint {
                    block["cache_control"] = ["type": "ephemeral"]
                }
                return block
            }
            body["system"] = systemBlocks
        }

        // Messages: user/assistant messages with optional cache_control
        let apiMessages: [[String: Any]] = userMessages.map { msg in
            var msgDict: [String: Any] = ["role": msg.role.rawValue]
            if msg.cacheHint {
                msgDict["content"] = [
                    ["type": "text", "text": msg.content, "cache_control": ["type": "ephemeral"]]
                ]
            } else {
                msgDict["content"] = msg.content
            }
            return msgDict
        }
        body["messages"] = apiMessages

        // Add output_config with JSON schema
        let schemaObject: Any
        do {
            schemaObject = try JSONSerialization.jsonObject(with: schema.schemaData)
        } catch {
            throw LLMEngineError.schemaError("Failed to deserialize schema data: \(error.localizedDescription)")
        }
        body["output_config"] = [
            "format": [
                "type": "json_schema",
                "schema": schemaObject,
            ] as [String: Any]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating structured output with Anthropic model \(config.model)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
        struct AnthropicResponse: Decodable {
            let content: [ContentBlock]
            let usage: Usage?
        }

        let anthropicResponse = try LLMHTTPHelpers.decodeResponse(AnthropicResponse.self, from: data)
        guard let text = anthropicResponse.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty else {
            throw LLMEngineError.emptyResponse
        }

        guard let outputData = text.data(using: .utf8) else {
            throw LLMEngineError.emptyResponse
        }

        let usage: TokenUsage
        if let u = anthropicResponse.usage {
            usage = TokenUsage(
                inputTokens: u.input_tokens ?? 0,
                outputTokens: u.output_tokens ?? 0,
                cacheCreationTokens: u.cache_creation_input_tokens ?? 0,
                cacheReadTokens: u.cache_read_input_tokens ?? 0
            )
            Self.logger.info("Anthropic structured usage: input=\(usage.inputTokens) output=\(usage.outputTokens) cache_create=\(usage.cacheCreationTokens) cache_read=\(usage.cacheReadTokens)")
        } else {
            usage = .zero
        }

        Self.logger.info("Anthropic structured generation complete (\(text.count) chars)")
        return StructuredOutput(data: outputData, usage: usage)
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        !config.apiKey.isEmpty
    }

}
