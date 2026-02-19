import Foundation
@testable import notetaker

nonisolated final class MockLLMEngine: LLMEngine, @unchecked Sendable {
    private let lock = NSLock()

    private var _generateCallCount = 0
    var generateCallCount: Int { lock.withLock { _generateCallCount } }

    private var _lastPrompt: String?
    var lastPrompt: String? { lock.withLock { _lastPrompt } }

    private var _lastConfig: LLMConfig?
    var lastConfig: LLMConfig? { lock.withLock { _lastConfig } }

    private var _stubbedResponse = "Mock LLM response"
    var stubbedResponse: String {
        get { lock.withLock { _stubbedResponse } }
        set { lock.withLock { _stubbedResponse = newValue } }
    }

    private var _stubbedResponses: [String]?
    /// When set, each call returns the next element; falls back to stubbedResponse when exhausted.
    var stubbedResponses: [String]? {
        get { lock.withLock { _stubbedResponses } }
        set { lock.withLock { _stubbedResponses = newValue } }
    }

    private var _allPrompts: [String] = []
    /// All prompts received across every generate() call, in order.
    var allPrompts: [String] { lock.withLock { _allPrompts } }

    private var _stubbedError: Error?
    var stubbedError: Error? {
        get { lock.withLock { _stubbedError } }
        set { lock.withLock { _stubbedError = newValue } }
    }

    private var _isAvailableResult = true
    var isAvailableResult: Bool {
        get { lock.withLock { _isAvailableResult } }
        set { lock.withLock { _isAvailableResult = newValue } }
    }

    func generate(prompt: String, config: LLMConfig) async throws -> String {
        let callIndex = lock.withLock { () -> Int in
            _generateCallCount += 1
            _lastPrompt = prompt
            _lastConfig = config
            _allPrompts.append(prompt)
            return _generateCallCount - 1
        }
        if let error = stubbedError {
            throw error
        }
        if let responses = stubbedResponses, callIndex < responses.count {
            return responses[callIndex]
        }
        return stubbedResponse
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        isAvailableResult
    }
}
