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
        lock.withLock {
            _generateCallCount += 1
            _lastPrompt = prompt
            _lastConfig = config
        }
        if let error = stubbedError {
            throw error
        }
        return stubbedResponse
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        isAvailableResult
    }
}
