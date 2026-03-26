import Foundation

nonisolated enum LLMEngineError: Error, LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case networkError(Error)
    case emptyResponse
    case notConfigured
    case notSupported
    case schemaError(String)

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
    }

    let role: Role
    let content: String
    /// Hint that this message's content is stable across calls and is a good candidate for prompt caching.
    let cacheHint: Bool
    /// Token usage statistics from the API response (populated on assistant messages returned by engines).
    let usage: TokenUsage?

    init(role: Role, content: String, cacheHint: Bool = false, usage: TokenUsage? = nil) {
        self.role = role
        self.content = content
        self.cacheHint = cacheHint
        self.usage = usage
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

nonisolated protocol LLMEngine: AnyObject, Sendable {
    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage
    func isAvailable(config: LLMConfig) async -> Bool
    var supportsStructuredOutput: Bool { get }
    func generateStructured(messages: [LLMMessage], schema: JSONSchema, config: LLMConfig) async throws -> StructuredOutput
}

extension LLMEngine {
    var supportsStructuredOutput: Bool { false }
    func generateStructured(messages: [LLMMessage], schema: JSONSchema, config: LLMConfig) async throws -> StructuredOutput {
        throw LLMEngineError.notSupported
    }
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

    /// Validate that a base URL uses http or https scheme, and normalize it.
    static func validateBaseURL(_ raw: String, stripV1: Bool = false) throws -> String {
        let normalized = normalizeBaseURL(raw, stripV1: stripV1)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LLMEngineError.invalidURL(raw)
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
