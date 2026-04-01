import Foundation
import os

nonisolated final class OpenAIEngine: LLMEngine, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.transcribenote", category: "OpenAIEngine")
    private let session: URLSession

    var supportsStructuredOutput: Bool { true }
    var supportsToolCalling: Bool { true }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            if let host = url.host, !host.hasSuffix("openai.com") && !host.contains("localhost") && host != "127.0.0.1" {
                Self.logger.warning("Sending API key to non-OpenAI host: \(host)")
            }
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Map LLMMessage array to OpenAI messages format
        let apiMessages: [[String: String]] = messages.filter { $0.role != .assistant }.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]
        // Pass enable_thinking for OpenAI-compatible servers (LM Studio, vLLM, etc.)
        body["chat_template_kwargs"] = ["enable_thinking": config.thinkingEnabled]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with OpenAI model \(config.model) (thinking: \(config.thinkingEnabled))")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct PromptTokensDetails: Decodable {
            let cached_tokens: Int?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let prompt_tokens_details: PromptTokensDetails?
        }
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        struct OpenAIResponse: Decodable {
            let choices: [Choice]
            let usage: Usage?
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

        let usage: TokenUsage
        if let u = openAIResponse.usage {
            usage = TokenUsage(
                inputTokens: u.prompt_tokens ?? 0,
                outputTokens: u.completion_tokens ?? 0,
                cacheCreationTokens: 0,
                cacheReadTokens: u.prompt_tokens_details?.cached_tokens ?? 0
            )
            Self.logger.info("OpenAI usage: input=\(usage.inputTokens) output=\(usage.outputTokens) cache_read=\(usage.cacheReadTokens)")
        } else {
            usage = .zero
        }

        Self.logger.info("OpenAI generation complete (\(result.count) chars)")
        return LLMMessage(role: .assistant, content: result, usage: usage)
    }

    func generateStructured(messages: [LLMMessage], schema: JSONSchema, config: LLMConfig) async throws -> StructuredOutput {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            if let host = url.host, !host.hasSuffix("openai.com") && !host.contains("localhost") && host != "127.0.0.1" {
                Self.logger.warning("Sending API key to non-OpenAI host: \(host)")
            }
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let apiMessages: [[String: String]] = messages.filter { $0.role != .assistant }.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        // Deserialize schema data to JSON object for embedding in request
        let schemaObject: Any
        do {
            schemaObject = try JSONSerialization.jsonObject(with: schema.schemaData)
        } catch {
            throw LLMEngineError.schemaError("Failed to deserialize schema data: \(error.localizedDescription)")
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "temperature": config.temperature,
            "max_tokens": config.maxTokens,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": schema.name,
                    "strict": schema.strict,
                    "schema": schemaObject
                ] as [String: Any]
            ] as [String: Any]
        ]
        body["chat_template_kwargs"] = ["enable_thinking": false]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating structured output with OpenAI model \(config.model), schema: \(schema.name)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct PromptTokensDetails: Decodable {
            let cached_tokens: Int?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let prompt_tokens_details: PromptTokensDetails?
        }
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        struct OpenAIResponse: Decodable {
            let choices: [Choice]
            let usage: Usage?
        }

        let openAIResponse = try LLMHTTPHelpers.decodeResponse(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content, !content.isEmpty else {
            throw LLMEngineError.emptyResponse
        }

        guard let outputData = content.data(using: .utf8) else {
            throw LLMEngineError.emptyResponse
        }

        let usage: TokenUsage
        if let u = openAIResponse.usage {
            usage = TokenUsage(
                inputTokens: u.prompt_tokens ?? 0,
                outputTokens: u.completion_tokens ?? 0,
                cacheCreationTokens: 0,
                cacheReadTokens: u.prompt_tokens_details?.cached_tokens ?? 0
            )
            Self.logger.info("OpenAI structured usage: input=\(usage.inputTokens) output=\(usage.outputTokens) cache_read=\(usage.cacheReadTokens)")
        } else {
            usage = .zero
        }

        Self.logger.info("OpenAI structured generation complete (\(content.count) chars)")
        return StructuredOutput(data: outputData, usage: usage)
    }

    func generateWithTools(messages: [LLMMessage], tools: [LLMTool], config: LLMConfig) async throws -> LLMToolResponse {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMEngineError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            if let host = url.host, !host.hasSuffix("openai.com") && !host.contains("localhost") && host != "127.0.0.1" {
                Self.logger.warning("Sending API key to non-OpenAI host: \(host)")
            }
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Build messages array supporting all roles including assistant with tool_calls and tool results
        var apiMessages: [[String: Any]] = []
        for msg in messages {
            switch msg.role {
            case .system, .user:
                apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
            case .assistant:
                var msgDict: [String: Any] = ["role": "assistant", "content": msg.content]
                if let calls = msg.toolCalls {
                    let callsArray: [[String: Any]] = calls.map { call in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": [
                                "name": call.name,
                                "arguments": String(data: call.arguments, encoding: .utf8) ?? "{}"
                            ]
                        ]
                    }
                    msgDict["tool_calls"] = callsArray
                }
                apiMessages.append(msgDict)
            case .tool:
                apiMessages.append([
                    "role": "tool",
                    "content": msg.content,
                    "tool_call_id": msg.toolCallId ?? ""
                ])
            }
        }

        // Build tools array
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
            "temperature": config.temperature,
            "max_tokens": config.maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Self.logger.info("Generating with tools using OpenAI model \(config.model)")

        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)

        struct ToolCallFunction: Decodable {
            let name: String
            let arguments: String
        }
        struct ToolCallItem: Decodable {
            let id: String
            let function: ToolCallFunction
        }
        struct PromptTokensDetails: Decodable {
            let cached_tokens: Int?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let prompt_tokens_details: PromptTokensDetails?
        }
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let tool_calls: [ToolCallItem]?
            }
            let message: Message
        }
        struct OpenAIResponse: Decodable {
            let choices: [Choice]
            let usage: Usage?
        }

        let openAIResponse = try LLMHTTPHelpers.decodeResponse(OpenAIResponse.self, from: data)
        guard let message = openAIResponse.choices.first?.message else {
            throw LLMEngineError.emptyResponse
        }

        let usage: TokenUsage
        if let u = openAIResponse.usage {
            usage = TokenUsage(
                inputTokens: u.prompt_tokens ?? 0,
                outputTokens: u.completion_tokens ?? 0,
                cacheCreationTokens: 0,
                cacheReadTokens: u.prompt_tokens_details?.cached_tokens ?? 0
            )
        } else {
            usage = .zero
        }

        if let toolCalls = message.tool_calls, !toolCalls.isEmpty {
            let calls = toolCalls.map { tc in
                LLMToolCall(
                    id: tc.id,
                    name: tc.function.name,
                    arguments: tc.function.arguments.data(using: .utf8) ?? Data()
                )
            }
            Self.logger.info("OpenAI returned \(calls.count) tool call(s)")
            return .toolCalls(calls, usage: usage)
        }

        let content = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw LLMEngineError.emptyResponse }

        Self.logger.info("OpenAI tool-calling generation complete (\(content.count) chars)")
        return .text(LLMMessage(role: .assistant, content: content, usage: usage))
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        guard let baseURL = try? LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
        ) else { return false }
        guard let url = URL(string: "\(baseURL)/models") else { return false }
        do {
            var request = URLRequest(url: url)
            if !config.apiKey.isEmpty {
                if let host = url.host, !host.hasSuffix("openai.com") && !host.contains("localhost") && host != "127.0.0.1" {
                    Self.logger.warning("Sending API key to non-OpenAI host: \(host)")
                }
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            }
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func listModels(config: LLMConfig) async throws -> [String] {
        let baseURL = try LLMHTTPHelpers.validateBaseURL(
            config.baseURL.isEmpty ? "https://api.openai.com/v1" : config.baseURL
        )
        guard let url = URL(string: "\(baseURL)/models") else {
            throw LLMEngineError.invalidURL("\(baseURL)/models")
        }
        var request = URLRequest(url: url)
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await LLMHTTPHelpers.performRequest(request, session: session)
        try LLMHTTPHelpers.validateHTTPResponse(response, data: data)
        let modelsResponse = try LLMHTTPHelpers.decodeResponse(OpenAIModelsResponse.self, from: data)
        let models = modelsResponse.data.map(\.id).sorted()
        Self.logger.info("OpenAI-compatible listed \(models.count) models")
        return models
    }

}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }
    let data: [Model]
}
