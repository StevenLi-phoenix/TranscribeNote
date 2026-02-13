import AVFoundation

/// A no-op ASR engine used as a fallback when the real speech recognizer is unavailable.
nonisolated final class NoopASREngine: ASREngine, @unchecked Sendable {
    var onResult: (@Sendable (TranscriptResult) -> Void)?
    var onError: (@Sendable (Error) -> Void)?
    var supportsOnDevice: Bool { false }

    func startRecognition(audioEngine: AVAudioEngine) throws {}
    func stopRecognition() {}
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {}
}
