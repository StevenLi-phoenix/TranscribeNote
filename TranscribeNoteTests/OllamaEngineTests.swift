import Foundation
import Testing
@testable import TranscribeNote

@Suite("OllamaEngine Tests", .serialized)
struct OllamaEngineTests {
    private let engine: OllamaEngine
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaMockProtocol.self]
        session = URLSession(configuration: config)
        engine = OllamaEngine(session: session)
    }

    private func makeConfig(model: String = "llama3", baseURL: String = "http://localhost:11434") -> LLMConfig {
        LLMConfig(provider: .ollama, model: model, apiKey: "", baseURL: baseURL, temperature: 0.7, maxTokens: 1024)
    }

    private func makeMessages(_ prompt: String) -> [LLMMessage] {
        [LLMMessage(role: .user, content: prompt)]
    }

    @Test("Successful generation returns trimmed response")
    func successfulGeneration() async throws {
        let responseJSON = """
        {"response": "  Hello from Ollama  "}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        #expect(result.content == "Hello from Ollama")
        #expect(result.role == .assistant)
    }

    @Test("Request format is correct")
    func requestFormat() async throws {
        let responseJSON = """
        {"response": "ok"}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OllamaMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test prompt"), config: makeConfig(model: "llama3"))

        let request = try #require(capturedRequest)
        #expect(request.url?.absoluteString == "http://localhost:11434/api/generate")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "llama3")
        #expect(json["prompt"] as? String == "test prompt")
        #expect(json["stream"] as? Bool == false)
    }

    @Test("System messages mapped to system field")
    func systemMessages() async throws {
        let responseJSON = """
        {"response": "ok"}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OllamaMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let messages = [
            LLMMessage(role: .system, content: "You are helpful"),
            LLMMessage(role: .user, content: "Hello"),
        ]
        _ = try await engine.generate(messages: messages, config: makeConfig())

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["system"] as? String == "You are helpful")
        #expect(json["prompt"] as? String == "Hello")
    }

    @Test("Token usage parsed from response")
    func tokenUsage() async throws {
        let responseJSON = """
        {"response": "ok", "prompt_eval_count": 42, "eval_count": 10}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(messages: makeMessages("test"), config: makeConfig())
        let usage = try #require(result.usage)
        #expect(usage.inputTokens == 42)
        #expect(usage.outputTokens == 10)
        #expect(usage.cacheCreationTokens == 0)
        #expect(usage.cacheReadTokens == 0)
    }

    @Test("HTTP error throws httpError")
    func httpError() async throws {
        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        }
    }

    @Test("Malformed JSON throws decodingError")
    func malformedJSON() async throws {
        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not json".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        }
    }

    @Test("Empty response throws emptyResponse")
    func emptyResponse() async throws {
        let responseJSON = """
        {"response": "   "}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(messages: makeMessages("Hello"), config: makeConfig())
        }
    }

    @Test("Custom baseURL is used")
    func customBaseURL() async throws {
        let responseJSON = """
        {"response": "ok"}
        """.data(using: .utf8)!

        var capturedURL: URL?
        OllamaMockProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(baseURL: "http://custom:8080"))
        #expect(capturedURL?.absoluteString == "http://custom:8080/api/generate")
    }

    @Test("Default baseURL used when empty")
    func defaultBaseURL() async throws {
        let responseJSON = """
        {"response": "ok"}
        """.data(using: .utf8)!

        var capturedURL: URL?
        OllamaMockProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generate(messages: makeMessages("test"), config: makeConfig(baseURL: ""))
        #expect(capturedURL?.absoluteString == "http://localhost:11434/api/generate")
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
        {"response": "{\\"name\\": \\"Jane\\", \\"age\\": 30}"}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateStructured(
            messages: makeMessages("Give me a person"),
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

    @Test("Structured output request includes format as JSON object")
    func structuredOutputRequestFormat() async throws {
        let responseJSON = """
        {"response": "{\\"name\\": \\"Jane\\", \\"age\\": 30}"}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OllamaMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generateStructured(
            messages: makeMessages("test"),
            schema: makeSchema(),
            config: makeConfig()
        )

        let request = try #require(capturedRequest)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        // format should be a JSON object (dictionary), not a string
        let format = try #require(json["format"] as? [String: Any])
        #expect(format["type"] as? String == "object")

        let properties = try #require(format["properties"] as? [String: Any])
        #expect(properties.keys.contains("name"))
        #expect(properties.keys.contains("age"))
    }

    @Test("Structured output token usage extracted from response")
    func structuredOutputTokenUsage() async throws {
        let responseJSON = """
        {"response": "{\\"name\\": \\"Jane\\", \\"age\\": 30}", "prompt_eval_count": 55, "eval_count": 20}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateStructured(
            messages: makeMessages("test"),
            schema: makeSchema(),
            config: makeConfig()
        )

        let usage = try #require(result.usage)
        #expect(usage.inputTokens == 55)
        #expect(usage.outputTokens == 20)
        #expect(usage.cacheCreationTokens == 0)
        #expect(usage.cacheReadTokens == 0)
    }

    @Test("Structured output empty response throws emptyResponse")
    func structuredOutputEmptyResponse() async throws {
        let responseJSON = """
        {"response": ""}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
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

    @Test("Structured output HTTP error throws httpError")
    func structuredOutputHTTPError() async throws {
        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, "Internal Server Error".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generateStructured(
                messages: makeMessages("test"),
                schema: makeSchema(),
                config: makeConfig()
            )
        }
    }

    // MARK: - Tool Calling Tests

    private func makeTool() -> LLMTool {
        let schemaData = try! JSONSerialization.data(withJSONObject: ["type": "object", "properties": ["q": ["type": "string"]]])
        let schema = JSONSchema(name: "params", description: "params", schemaData: schemaData)
        return LLMTool(name: "search", description: "Search the web", parameters: schema) { _ in "result" }
    }

    @Test("supportsToolCalling returns true")
    func supportsToolCalling() {
        #expect(engine.supportsToolCalling == true)
    }

    @Test("Tool calling uses /api/chat endpoint")
    func toolCallingEndpoint() async throws {
        let responseJSON = """
        {"message": {"role": "assistant", "content": "ok"}}
        """.data(using: .utf8)!

        var capturedURL: URL?
        OllamaMockProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generateWithTools(messages: makeMessages("test"), tools: [makeTool()], config: makeConfig())
        #expect(capturedURL?.absoluteString == "http://localhost:11434/api/chat")
    }

    @Test("Tool calling request format includes tools array")
    func toolCallingRequestFormat() async throws {
        let responseJSON = """
        {"message": {"role": "assistant", "content": "ok"}}
        """.data(using: .utf8)!

        var capturedRequest: URLRequest?
        OllamaMockProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        _ = try await engine.generateWithTools(messages: makeMessages("test"), tools: [makeTool()], config: makeConfig())

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try #require(json["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        let fn = try #require(tools[0]["function"] as? [String: Any])
        #expect(fn["name"] as? String == "search")
        #expect(json["stream"] as? Bool == false)

        // Verify messages are in chat format
        let apiMessages = try #require(json["messages"] as? [[String: Any]])
        #expect(apiMessages.count == 1)
        #expect(apiMessages[0]["role"] as? String == "user")
    }

    @Test("Tool calling text response")
    func toolCallingTextResponse() async throws {
        let responseJSON = """
        {"message": {"role": "assistant", "content": "  Text result  "}}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateWithTools(messages: makeMessages("test"), tools: [makeTool()], config: makeConfig())
        if case .text(let msg) = result {
            #expect(msg.content == "Text result")
        } else {
            Issue.record("Expected .text response")
        }
    }

    @Test("Tool calling returns toolCalls with synthetic IDs")
    func toolCallingToolCalls() async throws {
        let responseJSON = """
        {"message": {"role": "assistant", "content": "", "tool_calls": [{"function": {"name": "search", "arguments": {"q": "test"}}}]}, "prompt_eval_count": 15, "eval_count": 8}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateWithTools(messages: makeMessages("test"), tools: [makeTool()], config: makeConfig())
        if case .toolCalls(let calls, let usage) = result {
            #expect(calls.count == 1)
            #expect(calls[0].id == "ollama-0")
            #expect(calls[0].name == "search")
            #expect(usage?.inputTokens == 15)
            #expect(usage?.outputTokens == 8)
        } else {
            Issue.record("Expected .toolCalls response")
        }
    }

    @Test("Tool calling token usage extracted")
    func toolCallingTokenUsage() async throws {
        let responseJSON = """
        {"message": {"role": "assistant", "content": "ok"}, "prompt_eval_count": 30, "eval_count": 12}
        """.data(using: .utf8)!

        OllamaMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generateWithTools(messages: makeMessages("test"), tools: [makeTool()], config: makeConfig())
        if case .text(let msg) = result {
            let usage = try #require(msg.usage)
            #expect(usage.inputTokens == 30)
            #expect(usage.outputTokens == 12)
        } else {
            Issue.record("Expected .text response")
        }
    }
}
