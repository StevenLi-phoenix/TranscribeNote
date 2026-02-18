import Foundation
import Testing
@testable import notetaker

@Suite("AnthropicEngine Tests", .serialized)
struct AnthropicEngineTests {
    private let engine: AnthropicEngine
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AnthropicMockProtocol.self]
        session = URLSession(configuration: config)
        engine = AnthropicEngine(session: session)
    }

    private func makeConfig(
        model: String = "claude-sonnet-4-5-20250929",
        apiKey: String = "sk-ant-test-key",
        baseURL: String = "https://api.anthropic.com"
    ) -> LLMConfig {
        LLMConfig(provider: .anthropic, model: model, apiKey: apiKey, baseURL: baseURL, temperature: 0.7, maxTokens: 1024)
    }

    @Test("Successful generation returns text content")
    func successfulGeneration() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "  Hello from Anthropic  "}]}
        """.data(using: .utf8)!

        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(prompt: "Hello", config: makeConfig())
        #expect(result == "Hello from Anthropic")
    }

    @Test("x-api-key header is set")
    func apiKeyHeader() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        AnthropicMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(prompt: "test", config: makeConfig(apiKey: "sk-ant-my-key"))

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-my-key")
    }

    @Test("anthropic-version header is set")
    func versionHeader() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        AnthropicMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(prompt: "test", config: makeConfig())

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test("Request URL and format correct")
    func requestFormat() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        AnthropicMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(prompt: "test prompt", config: makeConfig(model: "claude-sonnet-4-5-20250929"))

        let request = try #require(capturedRequest)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-sonnet-4-5-20250929")
        #expect(json["max_tokens"] as? Int == 1024)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.first?["role"] == "user")
        #expect(messages.first?["content"] == "test prompt")
    }

    @Test("Custom baseURL is used")
    func customBaseURL() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedURL: URL?
        AnthropicMockProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(prompt: "test", config: makeConfig(baseURL: "https://custom.anthropic.com"))
        #expect(capturedURL?.absoluteString == "https://custom.anthropic.com/v1/messages")
    }

    @Test("HTTP error throws httpError")
    func httpError() async throws {
        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, "Rate limited".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(prompt: "Hello", config: makeConfig())
        }
    }

    @Test("Malformed JSON throws decodingError")
    func malformedJSON() async throws {
        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not json".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(prompt: "Hello", config: makeConfig())
        }
    }

    @Test("No text content throws emptyResponse")
    func noTextContent() async throws {
        let responseJSON = """
        {"content": [{"type": "image", "text": null}]}
        """.data(using: .utf8)!

        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(prompt: "Hello", config: makeConfig())
        }
    }

    @Test("Default baseURL used when empty")
    func defaultBaseURL() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedURL: URL?
        AnthropicMockProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(prompt: "test", config: makeConfig(baseURL: ""))
        #expect(capturedURL?.absoluteString == "https://api.anthropic.com/v1/messages")
    }
}
