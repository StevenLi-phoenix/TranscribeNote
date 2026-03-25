import Foundation
@testable import notetaker

nonisolated final class MockLLMEngine: LLMEngine, @unchecked Sendable {
    private let lock = NSLock()

    private var _generateCallCount = 0
    var generateCallCount: Int { lock.withLock { _generateCallCount } }

    private var _lastMessages: [LLMMessage]?
    var lastMessages: [LLMMessage]? { lock.withLock { _lastMessages } }

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

    private var _allMessages: [[LLMMessage]] = []
    /// All message arrays received across every generate() call, in order.
    var allMessages: [[LLMMessage]] { lock.withLock { _allMessages } }

    /// Convenience: returns the concatenated user message content from each call (for backward-compatible prompt assertions).
    var allPrompts: [String] {
        lock.withLock {
            _allMessages.map { msgs in
                msgs.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")
            }
        }
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

    func generate(messages: [LLMMessage], config: LLMConfig) async throws -> LLMMessage {
        let callIndex = lock.withLock { () -> Int in
            _generateCallCount += 1
            _lastMessages = messages
            _lastConfig = config
            _allMessages.append(messages)
            return _generateCallCount - 1
        }
        if let error = stubbedError {
            throw error
        }
        let content: String
        if let responses = stubbedResponses, callIndex < responses.count {
            content = responses[callIndex]
        } else {
            content = stubbedResponse
        }
        return LLMMessage(role: .assistant, content: content, usage: .zero)
    }

    func isAvailable(config: LLMConfig) async -> Bool {
        isAvailableResult
    }
}
