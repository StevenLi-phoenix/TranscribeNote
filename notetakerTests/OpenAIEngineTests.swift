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

    @Test("Successful generation returns content")
    func successfulGeneration() async throws {
        let responseJSON = """
        {"choices": [{"message": {"content": "  Hello from OpenAI  "}}]}
        """.data(using: .utf8)!

        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await engine.generate(prompt: "Hello", config: makeConfig())
        #expect(result == "Hello from OpenAI")
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

        _ = try await engine.generate(prompt: "test", config: makeConfig(apiKey: "sk-my-key"))

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

        _ = try await engine.generate(prompt: "test", config: makeConfig(apiKey: ""))

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

        _ = try await engine.generate(prompt: "test", config: makeConfig(baseURL: "https://custom.api.com/v1"))
        #expect(capturedURL?.absoluteString == "https://custom.api.com/v1/chat/completions")
    }

    @Test("Request body format is correct")
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

        _ = try await engine.generate(prompt: "test prompt", config: makeConfig(model: "gpt-4"))

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-4")
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.first?["role"] == "user")
        #expect(messages.first?["content"] == "test prompt")
    }

    @Test("HTTP error throws httpError")
    func httpError() async throws {
        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, "Unauthorized".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(prompt: "Hello", config: makeConfig())
        }
    }

    @Test("Malformed JSON throws decodingError")
    func malformedJSON() async throws {
        OpenAIMockProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not json".data(using: .utf8)!)
        }

        await #expect(throws: LLMEngineError.self) {
            try await engine.generate(prompt: "Hello", config: makeConfig())
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
            try await engine.generate(prompt: "Hello", config: makeConfig())
        }
    }
}
