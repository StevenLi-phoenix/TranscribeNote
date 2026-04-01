import Foundation
import AVFoundation
@testable import TranscribeNote

nonisolated final class MockASREngine: ASREngine, @unchecked Sendable {
    var onResult: (@Sendable (TranscriptResult) async -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let lock = NSLock()

    private var _isRecognizing = false
    var isRecognizing: Bool { lock.withLock { _isRecognizing } }

    private var _startCallCount = 0
    var startCallCount: Int { lock.withLock { _startCallCount } }

    private var _stopCallCount = 0
    var stopCallCount: Int { lock.withLock { _stopCallCount } }

    private var _shouldThrowOnStart = false
    var shouldThrowOnStart: Bool {
        get { lock.withLock { _shouldThrowOnStart } }
        set { lock.withLock { _shouldThrowOnStart = newValue } }
    }

    private var _appendedBufferCount = 0
    var appendedBufferCount: Int { lock.withLock { _appendedBufferCount } }

    private var _lastAppendedBuffer: AVAudioPCMBuffer?
    var lastAppendedBuffer: AVAudioPCMBuffer? { lock.withLock { _lastAppendedBuffer } }

    struct MockError: Error {
        let message: String
    }

    func startRecognition(audioEngine: AVAudioEngine) throws {
        if shouldThrowOnStart {
            throw MockError(message: "Mock start failure")
        }
        lock.withLock {
            _startCallCount += 1
            _isRecognizing = true
        }
    }

    func stopRecognition() async {
        lock.withLock {
            _stopCallCount += 1
            _isRecognizing = false
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            _appendedBufferCount += 1
            _lastAppendedBuffer = buffer
        }
    }

    func simulateResult(_ result: TranscriptResult) async {
        await onResult?(result)
    }

    func simulateError(_ error: Error) {
        onError?(error)
    }
}
