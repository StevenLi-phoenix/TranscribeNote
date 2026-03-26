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

    private func makeMessages(_ prompt: String) -> [LLMMessage] {
        [LLMMessage(role: .user, content: prompt)]
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

        let result = try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        #expect(result.content == "Hello from Anthropic")
        #expect(result.role == .assistant)
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

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(apiKey: "sk-ant-my-key"))

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-my-key")
    }

    @Test("anthropic-version and anthropic-beta headers are set")
    func headers() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        AnthropicMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig())

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "prompt-caching-2024-07-31")
    }

    @Test("System messages sent as system parameter with cache_control")
    func systemMessagesWithCaching() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        AnthropicMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let messages = [
            LLMMessage(role: .system, content: "You are helpful", cacheHint: true),
            LLMMessage(role: .user, content: "test prompt"),
        ]
        _ = try await engine.generate(messages: messages, config: makeConfig())

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        // System should be array of blocks with cache_control
        let system = try #require(json["system"] as? [[String: Any]])
        #expect(system.count == 1)
        #expect(system[0]["text"] as? String == "You are helpful")
        let cacheControl = try #require(system[0]["cache_control"] as? [String: String])
        #expect(cacheControl["type"] == "ephemeral")

        // Messages should only contain user messages
        let apiMessages = try #require(json["messages"] as? [[String: Any]])
        #expect(apiMessages.count == 1)
        #expect(apiMessages[0]["role"] as? String == "user")
        #expect(apiMessages[0]["content"] as? String == "test prompt")
    }

    @Test("User messages with cacheHint get cache_control")
    func userCacheHint() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        AnthropicMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let messages = [
            LLMMessage(role: .user, content: "cached context", cacheHint: true),
            LLMMessage(role: .user, content: "new content"),
        ]
        _ = try await engine.generate(messages: messages, config: makeConfig())

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let apiMessages = try #require(json["messages"] as? [[String: Any]])

        // First user message should have content as array with cache_control
        let firstContent = try #require(apiMessages[0]["content"] as? [[String: Any]])
        #expect(firstContent[0]["text"] as? String == "cached context")
        let cc = try #require(firstContent[0]["cache_control"] as? [String: String])
        #expect(cc["type"] == "ephemeral")

        // Second user message should have plain string content
        #expect(apiMessages[1]["content"] as? String == "new content")
    }

    @Test("Token usage with cache stats parsed from response")
    func tokenUsageWithCache() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}], "usage": {"input_tokens": 100, "output_tokens": 50, "cache_creation_input_tokens": 80, "cache_read_input_tokens": 0}}
        """.data(using: .utf8)!

        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(messages: makeMessages("test"), config: makeConfig())
        let usage = try #require(result.usage)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
        #expect(usage.cacheCreationTokens == 80)
        #expect(usage.cacheReadTokens == 0)
    }

    @Test("Cache read tokens on subsequent request")
    func cacheReadTokens() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}], "usage": {"input_tokens": 20, "output_tokens": 50, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 80}}
        """.data(using: .utf8)!

        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(messages: makeMessages("test"), config: makeConfig())
        let usage = try #require(result.usage)
        #expect(usage.cacheCreationTokens == 0)
        #expect(usage.cacheReadTokens == 80)
    }

    @Test("Request URL correct")
    func requestURL() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "ok"}]}
        """.data(using: .utf8)!

        var capturedURL: URL?
        AnthropicMockProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig())
        #expect(capturedURL?.absoluteString == "https://api.anthropic.com/v1/messages")
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

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(baseURL: "https://custom.anthropic.com"))
        #expect(capturedURL?.absoluteString == "https://custom.anthropic.com/v1/messages")
    }

    @Test("HTTP error throws httpError")
    func httpError() async throws {
        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, "Rate limited".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        }
    }

    @Test("Malformed JSON throws decodingError")
    func malformedJSON() async throws {
        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not json".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
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
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
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

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(baseURL: ""))
        #expect(capturedURL?.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    // MARK: - Structured Output Tests

    private func makeSchema() -> JSONSchema {
        let schemaDict: [String: Any] = [
            "type": "object",
            "properties": ["name": ["type": "string"], "age": ["type": "number"]],
            "required": ["name", "age"],
            "additionalProperties": false,
        ]
        let data = try! JSONSerialization.data(withJSONObject: schemaDict)
        return JSONSchema(name: "person", description: "A person", schemaData: data)
    }

    @Test("supportsStructuredOutput returns true")
    func supportsStructuredOutput() {
        #expect(engine.supportsStructuredOutput == true)
    }

    @Test("Structured output success decodes correctly")
    func structuredOutputSuccess() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "{\\"name\\": \\"Jane\\", \\"age\\": 30}"}]}
        """.data(using: .utf8)!

        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateStructured(
            messages: makeMessages("Generate a person"),
            schema: makeSchema(),
            config: makeConfig()
        )

        struct Person: Decodable {
            let name: String
            let age: Int
        }
        let person = try result.decode(Person.self)
        #expect(person.name == "Jane")
        #expect(person.age == 30)
    }

    @Test("Structured output request contains output_config with schema")
    func structuredOutputRequestFormat() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "{\\"name\\": \\"Test\\", \\"age\\": 1}"}]}
        """.data(using: .utf8)!

        var capturedBody: Data?
        AnthropicMockProtocol.requestHandler = { request in
            capturedBody = request.httpBody
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generateStructured(
            messages: makeMessages("test"),
            schema: makeSchema(),
            config: makeConfig()
        )

        let body = try #require(capturedBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        let outputConfig = try #require(json["output_config"] as? [String: Any])
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")

        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(properties.keys.contains("name"))
        #expect(properties.keys.contains("age"))
    }

    @Test("Structured output parses token usage")
    func structuredOutputTokenUsage() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": "{\\"name\\": \\"Test\\", \\"age\\": 1}"}], "usage": {"input_tokens": 200, "output_tokens": 30, "cache_creation_input_tokens": 150, "cache_read_input_tokens": 10}}
        """.data(using: .utf8)!

        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateStructured(
            messages: makeMessages("test"),
            schema: makeSchema(),
            config: makeConfig()
        )

        let usage = try #require(result.usage)
        #expect(usage.inputTokens == 200)
        #expect(usage.outputTokens == 30)
        #expect(usage.cacheCreationTokens == 150)
        #expect(usage.cacheReadTokens == 10)
    }

    @Test("Structured output with empty text throws emptyResponse")
    func structuredOutputEmptyContent() async throws {
        let responseJSON = """
        {"content": [{"type": "text", "text": ""}]}
        """.data(using: .utf8)!

        AnthropicMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generateStructured(
                messages: makeMessages("test"),
                schema: makeSchema(),
                config: makeConfig()
            )
        }
    }

    @Test("Structured output with missing apiKey throws notConfigured")
    func structuredOutputMissingApiKey() async throws {
        await #expect(throws: LLMEngineError.self) {
            try await engine.generateStructured(
                messages: makeMessages("test"),
                schema: makeSchema(),
                config: makeConfig(apiKey: "")
            )
        }
    }
}
