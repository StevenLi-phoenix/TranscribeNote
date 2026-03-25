import Foundation
import Testing
@testable import notetaker

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
}
