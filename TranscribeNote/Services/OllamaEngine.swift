import Foundation
import os

nonisolated final class OllamaEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.transcribenote", category: "OllamaEngine")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var supportsStructuredOutput: Bool { true }
    var supportsToolCalling: Bool { true }

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

    func generateStructured(messages: [LLMMessage], schema: JSONSchema, config: LLMConfig) async throws -> StructuredOutput {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Deserialize schema data into a JSON object for the format field
        let schemaObject: Any
        do {
            schemaObject = try JSONSerialization.jsonObject(with: schema.schemaData)
        } catch {
            throw LLMEngineError.schemaError("Failed to deserialize schema: \(error.localizedDescription)")
        }

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
            "think": config.thinkingEnabled,
            "format": schemaObject
        ]
        if !systemText.isEmpty {
            body["system"] = systemText
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating structured output with Ollama model \(config.model)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct OllamaResponse: Decodable {
            let response: String
            let prompt_eval_count: Int?
            let eval_count: Int?
        }

        let ollamaResponse = try LLMHTTPHelpers.decodeResponse(OllamaResponse.self, from: data)
        guard !ollamaResponse.response.isEmpty else { throw LLMEngineError.emptyResponse }

        guard let outputData = ollamaResponse.response.data(using: .utf8) else {
            throw LLMEngineError.emptyResponse
        }

        let usage = TokenUsage(
            inputTokens: ollamaResponse.prompt_eval_count ?? 0,
            outputTokens: ollamaResponse.eval_count ?? 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )
        Self.logger.info("Ollama structured output complete (\(ollamaResponse.response.count) chars), usage: input=\(usage.inputTokens) output=\(usage.outputTokens)")

        return StructuredOutput(data: outputData, usage: usage)
    }

    func generateWithTools(messages: [LLMMessage], tools: [LLMTool], config: LLMConfig) async throws -> LLMToolResponse {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build chat-format messages
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            switch msg.role {
            case .system, .user:
                apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
            case .assistant:
                var msgDict: [String: Any] = ["role": "assistant", "content": msg.content]
                if let calls = msg.toolCalls {
                    let callsArray: [[String: Any]] = calls.map { call in
                        let argsObject: Any = (try? JSONSerialization.jsonObject(with: call.arguments)) ?? [String: Any]()
                        return [
                            "function": [
                                "name": call.name,
                                "arguments": argsObject
                            ]
                        ]
                    }
                    msgDict["tool_calls"] = callsArray
                }
                apiMessages.append(msgDict)
            case .tool:
                apiMessages.append(["role": "tool", "content": msg.content])
            }
        }

        // Build tools array (OpenAI-compatible format)
        let toolsArray: [[String: Any]] = try tools.map { tool in
            let paramsObject = try JSONSerialization.jsonObject(with: tool.parameters.schemaData)
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": paramsObject
                ] as [String: Any]
            ]
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "tools": toolsArray,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with tools using Ollama model \(config.model)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        // Ollama chat response structure
        struct ToolCallFunction: Decodable {
            let name: String
            let arguments: OllamaAnyCodableValue?
        }
        struct ToolCallItem: Decodable {
            let function: ToolCallFunction
        }
        struct Message: Decodable {
            let role: String?
            let content: String?
            let tool_calls: [ToolCallItem]?
        }
        struct OllamaChatResponse: Decodable {
            let message: Message
            let prompt_eval_count: Int?
            let eval_count: Int?
        }

        let ollamaResponse = try LLMHTTPHelpers.decodeResponse(OllamaChatResponse.self, from: data)

        let usage = TokenUsage(
            inputTokens: ollamaResponse.prompt_eval_count ?? 0,
            outputTokens: ollamaResponse.eval_count ?? 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0
        )

        if let toolCalls = ollamaResponse.message.tool_calls, !toolCalls.isEmpty {
            let calls = toolCalls.enumerated().map { index, tc in
                let argsData: Data
                if let args = tc.function.arguments {
                    argsData = (try? JSONSerialization.data(withJSONObject: args.value)) ?? Data()
                } else {
                    argsData = Data()
                }
                return LLMToolCall(id: "ollama-\(index)", name: tc.function.name, arguments: argsData)
            }
            Self.logger.info("Ollama returned \(calls.count) tool call(s)")
            return .toolCalls(calls, usage: usage)
        }

        let content = (ollamaResponse.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw LLMEngineError.emptyResponse }

        Self.logger.info("Ollama tool-calling generation complete (\(content.count) chars)")
        return .text(LLMMessage(role: .assistant, content: content, usage: usage))
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

    func listModels(config: LLMConfig) async throws -> [String] {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "http://localhost:11434" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw LLMEngineError.invalidURL("\(baseURL)/api/tags")
        }
        let (data, response) = try await LLMHTTPHelpers.performRequest(URLRequest(url: url), session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)
        let tagsResponse = try LLMHTTPHelpers.decodeResponse(OllamaTagsResponse.self, from: data)
        let models = tagsResponse.models.map(\.name).sorted()
        Self.logger.info("Ollama listed \(models.count) models")
        return models
    }

}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }
    let models: [Model]
}

/// Helper for decoding arbitrary JSON values from Ollama tool call arguments.
private enum OllamaAnyCodableValue: Decodable {
    case dictionary([String: OllamaAnyCodableValue])
    case array([OllamaAnyCodableValue])
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
        } else if let arr = try? container.decode([OllamaAnyCodableValue].self) {
            self = .array(arr)
        } else if let dict = try? container.decode([String: OllamaAnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.typeMismatch(OllamaAnyCodableValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
