import Foundation

/// Helper class used solely to locate the test bundle.
final class TestBundleAnchor {}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }

    static let timeout = TestError("Condition not met within timeout")
}

/// Poll a condition with short intervals until it returns true or timeout is reached.
func waitForCondition(
    timeout: TimeInterval = 2.0,
    pollInterval: TimeInterval = 0.01,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(for: .seconds(pollInterval))
    }
    let result = await condition()
    if !result {
        throw TestError.timeout
    }
}

func sampleSpeechURL() throws -> URL {
    let bundle = Bundle(for: TestBundleAnchor.self)
    guard let url = bundle.url(forResource: "sample_speech", withExtension: "mp3") else {
        throw TestError("sample_speech.mp3 not found in test bundle")
    }
    return url
}

/// Simple thread-safe value wrapper for use in callbacks.
final class LockIsolated<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    var value: T { lock.withLock { _value } }
    init(_ value: T) { _value = value }
    func setValue(_ newValue: T) { lock.withLock { _value = newValue } }
}
