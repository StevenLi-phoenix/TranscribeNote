import Foundation
import Testing
@testable import notetaker

@Suite("OpenAIEngine Tests", .serialized)
struct OpenAIEngineTests {
    private let engine: OpenAIEngine
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIMockProtocol.self]
        session = URLSession(configuration: config)
        engine = OpenAIEngine(session: session)
    }

    private func makeConfig(
        model: String = "gpt-4",
        apiKey: String = "sk-test-key",
        baseURL: String = "https://api.openai.com/v1"
    ) -> LLMConfig {
        LLMConfig(provider: .openAI, model: model, apiKey: apiKey, baseURL: baseURL, temperature: 0.7, maxTokens: 1024)
    }

    private func makeMessages(_ prompt: String) -> [LLMMessage] {
        [LLMMessage(role: .user, content: prompt)]
    }

    @Test("Successful generation returns content")
    func successfulGeneration() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "  Hello from OpenAI  "}}]}
        """.data(using: .utf8)!

        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        #expect(result.content == "Hello from OpenAI")
        #expect(result.role == .assistant)
    }

    @Test("Bearer auth header present when apiKey set")
    func authHeaderPresent() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "ok"}}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OpenAIMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(apiKey: "sk-my-key"))

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-my-key")
    }

    @Test("No auth header when apiKey empty")
    func noAuthHeaderWhenEmpty() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "ok"}}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OpenAIMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(apiKey: ""))

        let request = try #require(capturedRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Custom baseURL used")
    func customBaseURL() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "ok"}}]}
        """.data(using: .utf8)!

        var capturedURL: URL?
        OpenAIMockProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(baseURL: "https://custom.api.com/v1"))
        #expect(capturedURL?.absoluteString == "https://custom.api.com/v1/chat/completions")
    }

    @Test("Request body format is correct with system and user messages")
    func requestFormat() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "ok"}}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OpenAIMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let messages = [
            LLMMessage(role: .system, content: "Be helpful"),
            LLMMessage(role: .user, content: "test prompt"),
        ]
        _ = try await engine.generate(messages: messages, config: makeConfig(model: "gpt-4"))

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-4")
        let apiMessages = try #require(json["messages"] as? [[String: String]])
        #expect(apiMessages.count == 2)
        #expect(apiMessages[0]["role"] == "system")
        #expect(apiMessages[0]["content"] == "Be helpful")
        #expect(apiMessages[1]["role"] == "user")
        #expect(apiMessages[1]["content"] == "test prompt")
    }

    @Test("Token usage parsed from response")
    func tokenUsage() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "ok"}}], "usage": {"prompt_tokens": 50, "completion_tokens": 20, "prompt_tokens_details": {"cached_tokens": 30}}}
        """.data(using: .utf8)!

        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(messages: makeMessages("test"), config: makeConfig())
        let usage = try #require(result.usage)
        #expect(usage.inputTokens == 50)
        #expect(usage.outputTokens == 20)
        #expect(usage.cacheReadTokens == 30)
        #expect(usage.cacheCreationTokens == 0)
    }

    @Test("HTTP error throws httpError")
    func httpError() async throws {
        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, "Unauthorized".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        }
    }

    @Test("Malformed JSON throws decodingError")
    func malformedJSON() async throws {
        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not json".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        }
    }

    @Test("Empty choices throws emptyResponse")
    func emptyChoices() async throws {
        let responseJSON = """
        {"choices": []}
        """.data(using: .utf8)!

        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        }
    }

    // MARK: - Structured Output Tests

    private func makeSchema() -> JSONSchema {
        let schemaDict: [String: Any] = [
            "type": "object",
            "properties": ["name": ["type": "string"], "age": ["type": "number"]],
            "required": ["name", "age"],
            "additionalProperties": false
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
        {"choices": [{"message": {"content": "{\\"name\\": \\"Jane\\", \\"age\\": 30}"}}]}
        """.data(using: .utf8)!

        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateStructured(
            messages: makeMessages("Extract person"),
            schema: makeSchema(),
            config: makeConfig()
        )

        struct Person: Decodable, Equatable {
            let name: String
            let age: Int
        }
        let person = try result.decode(Person.self)
        #expect(person.name == "Jane")
        #expect(person.age == 30)
    }

    @Test("Structured output request format contains response_format with schema")
    func structuredOutputRequestFormat() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "{\\"name\\": \\"Jane\\", \\"age\\": 30}"}}]}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OpenAIMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generateStructured(
            messages: makeMessages("Extract person"),
            schema: makeSchema(),
            config: makeConfig()
        )

        let request = try #require(capturedRequest)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        let responseFormat = try #require(json["response_format"] as? [String: Any])
        #expect(responseFormat["type"] as? String == "json_schema")

        let jsonSchema = try #require(responseFormat["json_schema"] as? [String: Any])
        #expect(jsonSchema["name"] as? String == "person")
        #expect(jsonSchema["strict"] as? Bool == true)

        let schema = try #require(jsonSchema["schema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(properties.keys.contains("name"))
        #expect(properties.keys.contains("age"))
    }

    @Test("Structured output token usage extraction")
    func structuredOutputTokenUsage() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "{\\"name\\": \\"Jane\\", \\"age\\": 30}"}}], "usage": {"prompt_tokens": 100, "completion_tokens": 15, "prompt_tokens_details": {"cached_tokens": 40}}}
        """.data(using: .utf8)!

        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateStructured(
            messages: makeMessages("Extract person"),
            schema: makeSchema(),
            config: makeConfig()
        )

        let usage = try #require(result.usage)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 15)
        #expect(usage.cacheReadTokens == 40)
        #expect(usage.cacheCreationTokens == 0)
    }

    @Test("Structured output empty content throws emptyResponse")
    func structuredOutputEmptyContent() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": ""}}]}
        """.data(using: .utf8)!

        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generateStructured(
                messages: makeMessages("Extract person"),
                schema: makeSchema(),
                config: makeConfig()
            )
        }
    }

    @Test("Structured output HTTP error throws httpError")
    func structuredOutputHTTPError() async throws {
        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generateStructured(
                messages: makeMessages("Extract person"),
                schema: makeSchema(),
                config: makeConfig()
            )
        }
    }
}
