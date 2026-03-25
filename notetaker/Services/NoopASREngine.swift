import AVFoundation
import os

/// A no-op ASR engine used as a fallback when the real speech recognizer is unavailable.
nonisolated final class NoopASREngine: ASREngine, @unchecked Sendable {
    private struct State: Sendable {
        var onResult: (@Sendable (TranscriptResult) async -> Void)?
        var onError: (@Sendable (Error) -> Void)?
    }

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    var onResult: (@Sendable (TranscriptResult) async -> Void)? {
        get { lock.withLock { $0.onResult } }
        set { lock.withLock { $0.onResult = newValue } }
    }

    var onError: (@Sendable (Error) -> Void)? {
        get { lock.withLock { $0.onError } }
        set { lock.withLock { $0.onError = newValue } }
    }

    func startRecognition(audioEngine: AVAudioEngine) throws {}
    func stopRecognition() async {}
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {}
}
