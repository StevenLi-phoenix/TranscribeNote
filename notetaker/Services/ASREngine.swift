import AVFoundation

nonisolated struct TranscriptResult: Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
    let language: String?
    let isFinal: Bool
}

nonisolated protocol ASREngine: AnyObject, Sendable {
    var onResult: (@Sendable (TranscriptResult) -> Void)? { get set }
    var onError: (@Sendable (Error) -> Void)? { get set }
    func startRecognition(audioEngine: AVAudioEngine) throws
    func stopRecognition()
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    var supportsOnDevice: Bool { get }
}
