import AVFoundation

nonisolated final class AudioCaptureService: @unchecked Sendable {
    let audioEngine = AVAudioEngine()
    private let ringBuffer: RingBuffer
    private var audioFile: AVAudioFile?
    private let config: AudioConfig

    /// External subscribers receive audio buffers (e.g., ASR engine).
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Called when a WAV file write error occurs during recording.
    var onWriteError: (@Sendable (Error) -> Void)?

    enum AudioCaptureError: Error {
        case microphonePermissionDenied
        case fileCreationFailed
        case recordingsDirectoryUnavailable
    }

    init(config: AudioConfig = .default) {
        self.config = config
        self.ringBuffer = RingBuffer(capacity: config.bufferCapacity)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start capture. Returns the WAV file URL for archival.
    func startCapture() throws -> URL {
        let recordingsDir = try Self.recordingsDirectory()
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).wav"
        let fileURL = recordingsDir.appendingPathComponent(filename)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        audioFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
        ringBuffer.reset()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Feed ring buffer
            if let channelData = buffer.floatChannelData, buffer.format.channelCount > 0 {
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                self.ringBuffer.write(samples)
            }

            // Write WAV archive
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                self.onWriteError?(error)
            }

            // Forward to subscribers (ASR engine)
            self.onAudioBuffer?(buffer)
        }

        try audioEngine.start()
        return fileURL
    }

    func stopCapture() -> URL? {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        let url = audioFile?.url
        audioFile = nil
        ringBuffer.reset()
        return url
    }

    static func recordingsDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AudioCaptureError.recordingsDirectoryUnavailable
        }
        return appSupport.appendingPathComponent("notetaker/Recordings", isDirectory: true)
    }
}
