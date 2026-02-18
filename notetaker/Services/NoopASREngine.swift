import AVFoundation

/// A no-op ASR engine used as a fallback when the real speech recognizer is unavailable.
nonisolated final class NoopASREngine: ASREngine, @unchecked Sendable {
    var onResult: (@Sendable (TranscriptResult) async -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    func startRecognition(audioEngine: AVAudioEngine) throws {}
    func stopRecognition() async {}
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {}
}
