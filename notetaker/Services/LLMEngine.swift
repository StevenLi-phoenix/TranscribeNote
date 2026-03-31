import Foundation
import os

nonisolated enum LLMEngineError: Error, LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(Error)
    case emptyResponse
    case notConfigured
    case notSupported
    case schemaError(String)
    case toolExecutionError(toolName: String, underlying: Error)
    case maxIterationsReached(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .httpError(let code, _): "LLM request failed (HTTP \(code)). Check your configuration."
        case .decodingError(let msg): "Decoding error: \(msg)"
        case .networkError(let err): "Network error: \(err.localizedDescription)"
        case .emptyResponse: "Empty response from LLM"
        case .notConfigured: "LLM not configured"
        case .notSupported: "Operation not supported by this engine"
        case .schemaError(let msg): "Schema error: \(msg)"
        case .toolExecutionError(let name, let err): "Tool '\(name)' execution failed: \(err.localizedDescription)"
        case .maxIterationsReached(let count): "Tool calling loop exceeded maximum iterations (\(count))"
        }
    }
}

/// Token usage statistics parsed from LLM API responses.
nonisolated struct TokenUsage: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    /// Tokens written to cache (Anthropic: first request that populates cache).
    let cacheCreationTokens: Int
    /// Tokens read from cache (Anthropic: subsequent requests; OpenAI: cached prefix tokens).
    let cacheReadTokens: Int

    static let zero = TokenUsage(inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0)
}

/// A structured message for LLM API calls.
nonisolated struct LLMMessage: Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    let role: Role
    let content: String
    /// Hint that this message's content is stable across calls and is a good candidate for prompt caching.
    let cacheHint: Bool
    /// Token usage statistics from the API response (populated on assistant messages returned by engines).
    let usage: TokenUsage?
    /// Tool calls returned by the assistant (populated when the LLM requests tool invocations).
    let toolCalls: [LLMToolCall]?
    /// The tool call ID this message is responding to (for .tool role messages).
    let toolCallId: String?

    init(role: Role, content: String, cacheHint: Bool = false, usage: TokenUsage? = nil, toolCalls: [LLMToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.cacheHint = cacheHint
        self.usage = usage
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// A JSON Schema definition for structured LLM output.
nonisolated struct JSONSchema: Sendable {
    let name: String
    let description: String
    /// Raw JSON Schema bytes (e.g. `{"type": "object", "properties": {...}}`).
    let schemaData: Data
    let strict: Bool

    init(name: String, description: String, schemaData: Data, strict: Bool = true) {
        self.name = name
        self.description = description
        self.schemaData = schemaData
        self.strict = strict
    }
}

/// Result of structured output generation — raw JSON bytes from the LLM.
nonisolated struct StructuredOutput: Sendable {
    let data: Data
    let usage: TokenUsage?

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMEngineError.schemaError("Failed to decode structured output: \(error.localizedDescription)")
        }
    }
}

/// A tool definition for LLM function calling.
nonisolated struct LLMTool: Sendable {
    let name: String
    let description: String
    let parameters: JSONSchema
    let handler: @Sendable (Data) async throws -> String
}

/// A single tool call returned by the LLM.
nonisolated struct LLMToolCall: Sendable, Equatable {
    let id: String
    let name: String
    let arguments: Data

    static func == (lhs: LLMToolCall, rhs: LLMToolCall) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.arguments == rhs.arguments
    }
}

/// Response from a tool-calling LLM request.
nonisolated enum LLMToolResponse: Sendable {
    case text(LLMMessage)
    case toolCalls([LLMToolCall], usage: TokenUsage?)
}

nonisolated protocol LLMEngine: AnyObject, Sendable {
    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage
    func isAvailable(config: LLMConfig) async -> Bool
    var supportsStructuredOutput: Bool { get }
    func generateStructured(messages: [LLMMessage], schema: JSONSchema, config: LLMConfig) async throws -> StructuredOutput
    var supportsToolCalling: Bool { get }
    func generateWithTools(messages: [LLMMessage], tools: [LLMTool], config: LLMConfig) async throws -> LLMToolResponse
}

extension LLMEngine {
    var supportsStructuredOutput: Bool { false }
    func generateStructured(messages: [LLMMessage], schema: JSONSchema, config: LLMConfig) async throws -> StructuredOutput {
        throw LLMEngineError.notSupported
    }
    var supportsToolCalling: Bool { false }
    func generateWithTools(messages: [LLMMessage], tools: [LLMTool], config: LLMConfig) async throws -> LLMToolResponse {
        throw LLMEngineError.notSupported
    }
}

/// Executes a tool-calling loop: repeatedly calls the engine, executes tool handlers, and feeds results back until the LLM returns a text response.
nonisolated func executeToolLoop(
    engine: any LLMEngine,
    messages: [LLMMessage],
    tools: [LLMTool],
    config: LLMConfig,
    maxIterations: Int = 10
) async throws -> LLMMessage {
    let logger = Logger(subsystem: "com.notetaker", category: "ToolLoop")
    let toolMap = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    var currentMessages = messages

    for iteration in 0..<maxIterations {
        logger.info("Tool loop iteration \(iteration + 1)/\(maxIterations)")
        let response = try await engine.generateWithTools(messages: currentMessages, tools: tools, config: config)

        switch response {
        case .text(let message):
            logger.info("Tool loop completed with text response after \(iteration + 1) iteration(s)")
            return message
        case .toolCalls(let calls, _):
            logger.info("Received \(calls.count) tool call(s)")
            // Append assistant message with tool calls
            currentMessages.append(LLMMessage(role: .assistant, content: "", toolCalls: calls))
            // Execute each tool and append results
            for call in calls {
                let resultContent: String
                if let tool = toolMap[call.name] {
                    do {
                        resultContent = try await tool.handler(call.arguments)
                        logger.info("Tool '\(call.name)' executed successfully")
                    } catch {
                        resultContent = "Error: \(error.localizedDescription)"
                        logger.warning("Tool '\(call.name)' failed: \(error.localizedDescription)")
                    }
                } else {
                    resultContent = "Error: Unknown tool '\(call.name)'"
                    logger.warning("Unknown tool requested: \(call.name)")
                }
                currentMessages.append(LLMMessage(role: .tool, content: resultContent, toolCallId: call.id))
            }
        }
    }

    logger.error("Tool loop exceeded max iterations (\(maxIterations))")
    throw LLMEngineError.maxIterationsReached(maxIterations)
}

/// Shared HTTP helpers for LLM engine implementations.
nonisolated enum LLMHTTPHelpers {
    static func performRequest(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            try Task.checkCancellation()
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LLMEngineError.networkError(error)
        }
    }

    static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            let truncated = String(body.prefix(200))
            throw LLMEngineError.httpError(statusCode: httpResponse.statusCode, body: truncated)
        }
    }

    static func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMEngineError.decodingError("Unexpected response format from LLM server")
        }
    }

    /// Normalize a base URL by stripping trailing slash and common path suffixes.
    /// e.g. "https://api.openai.com/v1/" → "https://api.openai.com/v1"
    /// e.g. "https://api.anthropic.com/v1" → "https://api.anthropic.com" (when stripV1 is true)
    static func normalizeBaseURL(_ raw: String, stripV1: Bool = false) -> String {
        var url = raw
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        if stripV1 && url.hasSuffix("/v1") { url = String(url.dropLast(3)) }
        return url
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMHTTPHelpers")

    /// Validate that a base URL uses http or https scheme, and normalize it.
    static func validateBaseURL(_ raw: String, stripV1: Bool = false) throws -> String {
        let normalized = normalizeBaseURL(raw, stripV1: stripV1)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LLMEngineError.invalidURL(raw)
        }
        // Warn when sending data over plaintext HTTP to a non-localhost host
        if scheme == "http",
           let host = url.host?.lowercased(),
           host != "localhost" && host != "127.0.0.1" && !host.hasPrefix("[::1]") {
            logger.warning("Using plaintext HTTP for remote host '\(host)' — transcript data may be exposed to network eavesdropping")
        }
        return normalized
    }

    /// Strip `<think>...</think>` blocks from model output when thinking is disabled.
    static func stripThinking(from text: String) -> String {
        text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
