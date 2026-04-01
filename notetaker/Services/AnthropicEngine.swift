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
    var supportsToolCalling: Bool { true }

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
        if let host = url.host, !host.hasSuffix("anthropic.com") && !host.contains("localhost") && host != "127.0.0.1" {
            Self.logger.warning("Sending API key to non-Anthropic host: \(host)")
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

    func generateWithTools(messages: [LLMMessage], tools: [LLMTool], config: LLMConfig) async throws -> LLMToolResponse {
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
        if let host = url.host, !host.hasSuffix("anthropic.com") && !host.contains("localhost") && host != "127.0.0.1" {
            Self.logger.warning("Sending API key to non-Anthropic host: \(host)")
        }
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

        // Build system parameter
        let systemMessages = messages.filter { $0.role == .system }
        let nonSystemMessages = messages.filter { $0.role != .system }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
        ]

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

        // Build messages supporting assistant with tool_use blocks and user with tool_result blocks
        var apiMessages: [[String: Any]] = []
        for msg in nonSystemMessages {
            switch msg.role {
            case .user:
                var msgDict: [String: Any] = ["role": "user"]
                if msg.cacheHint {
                    msgDict["content"] = [
                        ["type": "text", "text": msg.content, "cache_control": ["type": "ephemeral"]]
                    ]
                } else {
                    msgDict["content"] = msg.content
                }
                apiMessages.append(msgDict)
            case .assistant:
                if let calls = msg.toolCalls, !calls.isEmpty {
                    // Assistant message with tool_use content blocks
                    var contentBlocks: [[String: Any]] = []
                    if !msg.content.isEmpty {
                        contentBlocks.append(["type": "text", "text": msg.content])
                    }
                    for call in calls {
                        // AnyCodable: parse arguments JSON to Any for serialization
                        let inputObject: Any
                        if let parsed = try? JSONSerialization.jsonObject(with: call.arguments) {
                            inputObject = parsed
                        } else {
                            inputObject = [String: Any]()
                        }
                        contentBlocks.append([
                            "type": "tool_use",
                            "id": call.id,
                            "name": call.name,
                            "input": inputObject
                        ])
                    }
                    apiMessages.append(["role": "assistant", "content": contentBlocks])
                } else {
                    apiMessages.append(["role": "assistant", "content": msg.content])
                }
            case .tool:
                // Tool results sent as user message with tool_result content block
                apiMessages.append([
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result",
                            "tool_use_id": msg.toolCallId ?? "",
                            "content": msg.content
                        ]
                    ]
                ])
            case .system:
                break // Already handled above
            }
        }
        body["messages"] = apiMessages

        // Build tools array
        let toolsArray: [[String: Any]] = try tools.map { tool in
            let schemaObject = try JSONSerialization.jsonObject(with: tool.parameters.schemaData)
            return [
                "name": tool.name,
                "description": tool.description,
                "input_schema": schemaObject
            ]
        }
        body["tools"] = toolsArray

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with tools using Anthropic model \(config.model)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
            let id: String?
            let name: String?
            let input: AnyCodableValue?
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

        let usage: TokenUsage
        if let u = anthropicResponse.usage {
            usage = TokenUsage(
                inputTokens: u.input_tokens ?? 0,
                outputTokens: u.output_tokens ?? 0,
                cacheCreationTokens: u.cache_creation_input_tokens ?? 0,
                cacheReadTokens: u.cache_read_input_tokens ?? 0
            )
        } else {
            usage = .zero
        }

        // Check for tool_use blocks
        let toolUseBlocks = anthropicResponse.content.filter { $0.type == "tool_use" }
        if !toolUseBlocks.isEmpty {
            let calls = toolUseBlocks.compactMap { block -> LLMToolCall? in
                guard let id = block.id, let name = block.name else { return nil }
                let argsData: Data
                if let input = block.input {
                    argsData = (try? JSONSerialization.data(withJSONObject: input.value)) ?? Data()
                } else {
                    argsData = Data()
                }
                return LLMToolCall(id: id, name: name, arguments: argsData)
            }
            Self.logger.info("Anthropic returned \(calls.count) tool call(s)")
            return .toolCalls(calls, usage: usage)
        }

        // Text response
        guard let text = anthropicResponse.content.first(where: { $0.type == "text" })?.text else {
            throw LLMEngineError.emptyResponse
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LLMEngineError.emptyResponse }

        Self.logger.info("Anthropic tool-calling generation complete (\(result.count) chars)")
        return .text(LLMMessage(role: .assistant, content: result, usage: usage))
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        !config.apiKey.isEmpty
    }

    func listModels(config: LLMConfig) async throws -> [String] {
        guard !config.apiKey.isEmpty else { throw LLMEngineError.notConfigured }
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "https://api.anthropic.com" : config.baseURL,
            stripV1: true
        )
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            throw LLMEngineError.invalidURL("\(baseURL)/v1/models")
        }
        var request = URLRequest(url: url)
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)
        let modelsResponse = try LLMHTTPHelpers.decodeResponse(AnthropicModelsResponse.self, from: data)
        let models = modelsResponse.data.map(\.id).sorted()
        Self.logger.info("Anthropic listed \(models.count) models")
        return models
    }

}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }
    let data: [Model]
}

/// Helper for decoding arbitrary JSON values from Anthropic tool_use input.
private enum AnyCodableValue: Decodable {
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var value: Any {
        switch self {
        case .dictionary(let dict):
            return dict.mapValues { $0.value }
        case .array(let arr):
            return arr.map { $0.value }
        case .string(let s):
            return s
        case .number(let n):
            return n
        case .bool(let b):
            return b
        case .null:
            return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.typeMismatch(AnyCodableValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
