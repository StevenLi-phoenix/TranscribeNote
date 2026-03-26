import Testing
import Foundation
import AVFoundation
@testable import notetaker

@Suite("NoopASREngine Tests", .serialized)
struct NoopASREngineTests {

    @Test func onResultGetSet() {
        let engine = NoopASREngine()
        #expect(engine.onResult == nil)

        let handler: @Sendable (TranscriptResult) async -> Void = { _ in }
        engine.onResult = handler
        #expect(engine.onResult != nil)

        engine.onResult = nil
        #expect(engine.onResult == nil)
    }

    @Test func onErrorGetSet() {
        let engine = NoopASREngine()
        #expect(engine.onError == nil)

        let handler: @Sendable (Error) -> Void = { _ in }
        engine.onError = handler
        #expect(engine.onError != nil)

        engine.onError = nil
        #expect(engine.onError == nil)
    }

    @Test func startRecognitionDoesNotThrow() throws {
        let engine = NoopASREngine()
        let audioEngine = AVAudioEngine()
        try engine.startRecognition(audioEngine: audioEngine)
    }

    @Test func stopRecognitionCompletes() async {
        let engine = NoopASREngine()
        await engine.stopRecognition()
    }

    @Test func appendAudioBufferDoesNotCrash() {
        let engine = NoopASREngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        engine.appendAudioBuffer(buffer)
    }
}

@Suite("NoopLLMEngine Tests")
struct NoopLLMEngineTests {

    @Test func generateReturnsEmptyAssistantMessage() async throws {
        let engine = NoopLLMEngine()
        let message = try await engine.generate(messages: [], config: .default)
        #expect(message.role == .assistant)
        #expect(message.content == "")
        #expect(message.usage == .zero)
    }

    @Test func isAvailableReturnsFalse() async {
        let engine = NoopLLMEngine()
        let available = await engine.isAvailable(config: .default)
        #expect(available == false)
    }

    @Test func generateWithMessagesReturnsEmpty() async throws {
        let engine = NoopLLMEngine()
        let messages = [
            LLMMessage(role: .system, content: "You are a helper"),
            LLMMessage(role: .user, content: "Hello"),
        ]
        let result = try await engine.generate(messages: messages, config: .default)
        #expect(result.content == "")
    }

    @Test func supportsStructuredOutputReturnsFalse() {
        let engine = NoopLLMEngine()
        #expect(engine.supportsStructuredOutput == false)
    }

    @Test func generateStructuredThrowsNotSupported() async {
        let engine = NoopLLMEngine()
        let schemaData = try! JSONSerialization.data(withJSONObject: ["type": "object"])
        let schema = JSONSchema(name: "test", description: "test", schemaData: schemaData)
        await #expect(throws: LLMEngineError.self) {
            try await engine.generateStructured(messages: [], schema: schema, config: .default)
        }
    }
}

@Suite("JSONSchema Tests")
struct JSONSchemaTests {

    @Test func initWithDefaults() {
        let data = try! JSONSerialization.data(withJSONObject: ["type": "object"])
        let schema = JSONSchema(name: "test", description: "A test schema", schemaData: data)
        #expect(schema.name == "test")
        #expect(schema.description == "A test schema")
        #expect(schema.schemaData == data)
        #expect(schema.strict == true)
    }

    @Test func initWithStrictFalse() {
        let data = try! JSONSerialization.data(withJSONObject: ["type": "object"])
        let schema = JSONSchema(name: "test", description: "test", schemaData: data, strict: false)
        #expect(schema.strict == false)
    }
}

@Suite("StructuredOutput Tests")
struct StructuredOutputTests {

    private struct Person: Decodable, Equatable {
        let name: String
        let age: Int
    }

    @Test func decodeSuccess() throws {
        let json = #"{"name": "Jane", "age": 30}"#
        let output = StructuredOutput(data: json.data(using: .utf8)!, usage: .zero)
        let person = try output.decode(Person.self)
        #expect(person.name == "Jane")
        #expect(person.age == 30)
    }

    @Test func decodeFailureThrowsSchemaError() {
        let output = StructuredOutput(data: "not json".data(using: .utf8)!, usage: nil)
        #expect(throws: LLMEngineError.self) {
            try output.decode(Person.self)
        }
    }

    @Test func usagePreserved() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 5, cacheCreationTokens: 0, cacheReadTokens: 0)
        let output = StructuredOutput(data: Data(), usage: usage)
        #expect(output.usage == usage)
    }
}

@Suite("AudioExportError Tests")
struct AudioExportErrorTests {

    @Test func noFilesDescription() {
        let error = AudioExportError.noFiles
        #expect(error.errorDescription == "No audio files to export")
    }

    @Test func compositionFailedDescription() {
        let error = AudioExportError.compositionFailed
        #expect(error.errorDescription == "Failed to create audio composition")
    }

    @Test func exportSessionFailedDescription() {
        let error = AudioExportError.exportSessionFailed
        #expect(error.errorDescription == "Failed to create export session")
    }

    @Test func exportFailedDescription() {
        let error = AudioExportError.exportFailed("timeout")
        #expect(error.errorDescription == "Audio export failed: timeout")
    }
}

@Suite("LLMEngineError Tests")
struct LLMEngineErrorTests {

    @Test func invalidURLDescription() {
        let error = LLMEngineError.invalidURL("http://bad url")
        #expect(error.errorDescription?.contains("Invalid URL") == true)
    }

    @Test func httpErrorDescription() {
        let error = LLMEngineError.httpError(statusCode: 500, body: "Internal Server Error")
        #expect(error.errorDescription?.contains("500") == true)
    }

    @Test func decodingErrorDescription() {
        let error = LLMEngineError.decodingError("unexpected format")
        #expect(error.errorDescription?.contains("Decoding error") == true)
    }

    @Test func networkErrorDescription() {
        let underlying = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
        let error = LLMEngineError.networkError(underlying)
        #expect(error.errorDescription?.contains("Network error") == true)
    }

    @Test func emptyResponseDescription() {
        let error = LLMEngineError.emptyResponse
        #expect(error.errorDescription?.contains("Empty response") == true)
    }

    @Test func notConfiguredDescription() {
        let error = LLMEngineError.notConfigured
        #expect(error.errorDescription?.contains("not configured") == true)
    }

    @Test func notSupportedDescription() {
        let error = LLMEngineError.notSupported
        #expect(error.errorDescription?.contains("not supported") == true)
    }

    @Test func schemaErrorDescription() {
        let error = LLMEngineError.schemaError("invalid type")
        #expect(error.errorDescription?.contains("Schema error") == true)
        #expect(error.errorDescription?.contains("invalid type") == true)
    }
}

@Suite("TokenUsage Tests")
struct TokenUsageTests {

    @Test func zeroConstant() {
        let zero = TokenUsage.zero
        #expect(zero.inputTokens == 0)
        #expect(zero.outputTokens == 0)
        #expect(zero.cacheCreationTokens == 0)
        #expect(zero.cacheReadTokens == 0)
    }

    @Test func customValues() {
        let usage = TokenUsage(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 10, cacheReadTokens: 5)
        #expect(usage.inputTokens == 100)
        #expect(usage.outputTokens == 50)
        #expect(usage.cacheCreationTokens == 10)
        #expect(usage.cacheReadTokens == 5)
    }

    @Test func equatable() {
        let a = TokenUsage(inputTokens: 10, outputTokens: 20, cacheCreationTokens: 0, cacheReadTokens: 0)
        let b = TokenUsage(inputTokens: 10, outputTokens: 20, cacheCreationTokens: 0, cacheReadTokens: 0)
        #expect(a == b)
    }
}

@Suite("LLMMessage Tests")
struct LLMMessageTests {

    @Test func initDefaults() {
        let msg = LLMMessage(role: .user, content: "Hello")
        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
        #expect(msg.cacheHint == false)
        #expect(msg.usage == nil)
    }

    @Test func initWithAllParams() {
        let usage = TokenUsage(inputTokens: 5, outputTokens: 10, cacheCreationTokens: 0, cacheReadTokens: 0)
        let msg = LLMMessage(role: .assistant, content: "Hi", cacheHint: true, usage: usage)
        #expect(msg.role == .assistant)
        #expect(msg.content == "Hi")
        #expect(msg.cacheHint == true)
        #expect(msg.usage == usage)
    }

    @Test func roleRawValues() {
        #expect(LLMMessage.Role.system.rawValue == "system")
        #expect(LLMMessage.Role.user.rawValue == "user")
        #expect(LLMMessage.Role.assistant.rawValue == "assistant")
    }
}
