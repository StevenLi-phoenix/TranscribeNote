import Foundation
import Testing
@testable import TranscribeNote

// MARK: - Tool Calling Type Tests

@Suite("ToolCallingType Tests")
struct ToolCallingTypeTests {

    @Test("LLMToolCall equatable with matching fields")
    func toolCallEquatable() {
        let args = #"{"key": "value"}"#.data(using: .utf8)!
        let a = LLMToolCall(id: "tc-1", name: "search", arguments: args)
        let b = LLMToolCall(id: "tc-1", name: "search", arguments: args)
        #expect(a == b)
    }

    @Test("LLMToolCall not equal with different id")
    func toolCallNotEqualId() {
        let args = Data()
        let a = LLMToolCall(id: "tc-1", name: "search", arguments: args)
        let b = LLMToolCall(id: "tc-2", name: "search", arguments: args)
        #expect(a != b)
    }

    @Test("LLMToolCall not equal with different name")
    func toolCallNotEqualName() {
        let args = Data()
        let a = LLMToolCall(id: "tc-1", name: "search", arguments: args)
        let b = LLMToolCall(id: "tc-1", name: "lookup", arguments: args)
        #expect(a != b)
    }

    @Test("LLMToolCall not equal with different arguments")
    func toolCallNotEqualArgs() {
        let a = LLMToolCall(id: "tc-1", name: "search", arguments: "a".data(using: .utf8)!)
        let b = LLMToolCall(id: "tc-1", name: "search", arguments: "b".data(using: .utf8)!)
        #expect(a != b)
    }

    @Test("LLMMessage with .tool role")
    func messageWithToolRole() {
        let msg = LLMMessage(role: .tool, content: "result", toolCallId: "tc-1")
        #expect(msg.role == .tool)
        #expect(msg.content == "result")
        #expect(msg.toolCallId == "tc-1")
        #expect(msg.toolCalls == nil)
    }

    @Test("LLMMessage with toolCalls")
    func messageWithToolCalls() {
        let calls = [LLMToolCall(id: "tc-1", name: "fn", arguments: Data())]
        let msg = LLMMessage(role: .assistant, content: "", toolCalls: calls)
        #expect(msg.toolCalls?.count == 1)
        #expect(msg.toolCalls?.first?.name == "fn")
        #expect(msg.toolCallId == nil)
    }

    @Test("LLMMessage defaults for toolCalls and toolCallId")
    func messageDefaults() {
        let msg = LLMMessage(role: .user, content: "Hello")
        #expect(msg.toolCalls == nil)
        #expect(msg.toolCallId == nil)
    }

    @Test("LLMMessage.Role.tool raw value")
    func toolRoleRawValue() {
        #expect(LLMMessage.Role.tool.rawValue == "tool")
    }

    @Test("LLMToolResponse text case")
    func toolResponseText() {
        let msg = LLMMessage(role: .assistant, content: "done")
        let response = LLMToolResponse.text(msg)
        if case .text(let m) = response {
            #expect(m.content == "done")
        } else {
            Issue.record("Expected .text case")
        }
    }

    @Test("LLMToolResponse toolCalls case")
    func toolResponseToolCalls() {
        let calls = [LLMToolCall(id: "1", name: "fn", arguments: Data())]
        let usage = TokenUsage(inputTokens: 10, outputTokens: 5, cacheCreationTokens: 0, cacheReadTokens: 0)
        let response = LLMToolResponse.toolCalls(calls, usage: usage)
        if case .toolCalls(let c, let u) = response {
            #expect(c.count == 1)
            #expect(u?.inputTokens == 10)
        } else {
            Issue.record("Expected .toolCalls case")
        }
    }

    @Test("LLMTool properties accessible")
    func toolProperties() {
        let schemaData = try! JSONSerialization.data(withJSONObject: ["type": "object"])
        let schema = JSONSchema(name: "params", description: "params", schemaData: schemaData)
        let tool = LLMTool(name: "search", description: "Search the web", parameters: schema) { _ in "result" }
        #expect(tool.name == "search")
        #expect(tool.description == "Search the web")
    }
}

// MARK: - Tool Calling Error Tests

@Suite("ToolCallingError Tests")
struct ToolCallingErrorTests {

    @Test("toolExecutionError description contains tool name")
    func toolExecutionErrorDescription() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
        let error = LLMEngineError.toolExecutionError(toolName: "search", underlying: underlying)
        #expect(error.errorDescription?.contains("search") == true)
        #expect(error.errorDescription?.contains("timeout") == true)
    }

    @Test("maxIterationsReached description contains count")
    func maxIterationsReachedDescription() {
        let error = LLMEngineError.maxIterationsReached(10)
        #expect(error.errorDescription?.contains("10") == true)
        #expect(error.errorDescription?.contains("maximum iterations") == true)
    }
}

// MARK: - Execute Tool Loop Tests

@Suite("ExecuteToolLoop Tests", .serialized)
struct ExecuteToolLoopTests {

    private func makeConfig() -> LLMConfig {
        LLMConfig(provider: .custom, model: "test", apiKey: "", baseURL: "http://localhost", temperature: 0.7, maxTokens: 1024)
    }

    private func makeSchema() -> JSONSchema {
        let data = try! JSONSerialization.data(withJSONObject: ["type": "object"])
        return JSONSchema(name: "params", description: "params", schemaData: data)
    }

    @Test("Direct text response returns immediately")
    func directTextResponse() async throws {
        let engine = MockLLMEngine()
        engine.stubbedToolResponse = .text(LLMMessage(role: .assistant, content: "Hello"))

        let tool = LLMTool(name: "search", description: "Search", parameters: makeSchema()) { _ in "result" }
        let result = try await executeToolLoop(engine: engine, messages: [LLMMessage(role: .user, content: "Hi")], tools: [tool], config: makeConfig())

        #expect(result.content == "Hello")
        #expect(engine.generateWithToolsCallCount == 1)
    }

    @Test("Tool call then text response")
    func toolCallThenText() async throws {
        let engine = MockLLMEngine()
        let toolCall = LLMToolCall(id: "tc-1", name: "search", arguments: #"{"q":"test"}"#.data(using: .utf8)!)

        engine.stubbedToolResponses = [
            .toolCalls([toolCall], usage: .zero),
            .text(LLMMessage(role: .assistant, content: "Found result"))
        ]

        var handlerCalled = false
        let tool = LLMTool(name: "search", description: "Search", parameters: makeSchema()) { args in
            handlerCalled = true
            return "search result"
        }

        let result = try await executeToolLoop(engine: engine, messages: [LLMMessage(role: .user, content: "Search")], tools: [tool], config: makeConfig())

        #expect(result.content == "Found result")
        #expect(handlerCalled)
        #expect(engine.generateWithToolsCallCount == 2)

        // Verify second call includes tool result messages
        let secondCallMessages = engine.allMessages[1]
        let toolMessages = secondCallMessages.filter { $0.role == .tool }
        #expect(toolMessages.count == 1)
        #expect(toolMessages.first?.content == "search result")
        #expect(toolMessages.first?.toolCallId == "tc-1")
    }

    @Test("Unknown tool returns error message")
    func unknownTool() async throws {
        let engine = MockLLMEngine()
        let toolCall = LLMToolCall(id: "tc-1", name: "unknown_tool", arguments: Data())

        engine.stubbedToolResponses = [
            .toolCalls([toolCall], usage: .zero),
            .text(LLMMessage(role: .assistant, content: "OK"))
        ]

        let tool = LLMTool(name: "search", description: "Search", parameters: makeSchema()) { _ in "result" }

        let result = try await executeToolLoop(engine: engine, messages: [LLMMessage(role: .user, content: "test")], tools: [tool], config: makeConfig())

        #expect(result.content == "OK")
        // Verify error message was sent for unknown tool
        let secondCallMessages = engine.allMessages[1]
        let toolMessages = secondCallMessages.filter { $0.role == .tool }
        #expect(toolMessages.first?.content.contains("Unknown tool") == true)
    }

    @Test("Tool handler error returns error message")
    func toolHandlerError() async throws {
        let engine = MockLLMEngine()
        let toolCall = LLMToolCall(id: "tc-1", name: "failing", arguments: Data())

        engine.stubbedToolResponses = [
            .toolCalls([toolCall], usage: .zero),
            .text(LLMMessage(role: .assistant, content: "Handled"))
        ]

        let tool = LLMTool(name: "failing", description: "Always fails", parameters: makeSchema()) { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        }

        let result = try await executeToolLoop(engine: engine, messages: [LLMMessage(role: .user, content: "test")], tools: [tool], config: makeConfig())

        #expect(result.content == "Handled")
        let secondCallMessages = engine.allMessages[1]
        let toolMessages = secondCallMessages.filter { $0.role == .tool }
        #expect(toolMessages.first?.content.contains("Error:") == true)
    }

    @Test("Max iterations exceeded throws maxIterationsReached")
    func maxIterationsExceeded() async throws {
        let engine = MockLLMEngine()
        let toolCall = LLMToolCall(id: "tc-1", name: "search", arguments: Data())

        // Always return tool calls, never text
        engine.stubbedToolResponse = .toolCalls([toolCall], usage: .zero)

        let tool = LLMTool(name: "search", description: "Search", parameters: makeSchema()) { _ in "result" }

        await #expect(throws: LLMEngineError.self) {
            try await executeToolLoop(engine: engine, messages: [LLMMessage(role: .user, content: "test")], tools: [tool], config: makeConfig(), maxIterations: 3)
        }
        #expect(engine.generateWithToolsCallCount == 3)
    }

    @Test("Multiple tool calls in single response")
    func multipleToolCalls() async throws {
        let engine = MockLLMEngine()
        let call1 = LLMToolCall(id: "tc-1", name: "search", arguments: #"{"q":"a"}"#.data(using: .utf8)!)
        let call2 = LLMToolCall(id: "tc-2", name: "lookup", arguments: #"{"id":"1"}"#.data(using: .utf8)!)

        engine.stubbedToolResponses = [
            .toolCalls([call1, call2], usage: .zero),
            .text(LLMMessage(role: .assistant, content: "Combined results"))
        ]

        var searchCalled = false
        var lookupCalled = false

        let searchTool = LLMTool(name: "search", description: "Search", parameters: makeSchema()) { _ in
            searchCalled = true
            return "search result"
        }
        let lookupTool = LLMTool(name: "lookup", description: "Lookup", parameters: makeSchema()) { _ in
            lookupCalled = true
            return "lookup result"
        }

        let result = try await executeToolLoop(
            engine: engine,
            messages: [LLMMessage(role: .user, content: "test")],
            tools: [searchTool, lookupTool],
            config: makeConfig()
        )

        #expect(result.content == "Combined results")
        #expect(searchCalled)
        #expect(lookupCalled)

        // Verify both tool results in second call
        let secondCallMessages = engine.allMessages[1]
        let toolMessages = secondCallMessages.filter { $0.role == .tool }
        #expect(toolMessages.count == 2)
    }
}
