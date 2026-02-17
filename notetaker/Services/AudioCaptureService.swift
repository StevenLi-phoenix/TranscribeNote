import AVFoundation
import os

nonisolated final class AudioCaptureService: @unchecked Sendable {
    private(set) var audioEngine = AVAudioEngine()
    private let ringBuffer: RingBuffer
    private let config: AudioConfig
    private let lock: OSAllocatedUnfairLock<State>

    private struct State: Sendable {
        var audioFile: AVAudioFile?
        var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
        var onWriteError: (@Sendable (Error) -> Void)?
    }

    /// External subscribers receive audio buffers (e.g., ASR engine).
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { lock.withLock { $0.onAudioBuffer } }
        set { lock.withLock { $0.onAudioBuffer = newValue } }
    }

    /// Called when a WAV file write error occurs during recording.
    var onWriteError: (@Sendable (Error) -> Void)? {
        get { lock.withLock { $0.onWriteError } }
        set { lock.withLock { $0.onWriteError = newValue } }
    }

    enum AudioCaptureError: Error {
        case microphonePermissionDenied
        case fileCreationFailed
        case recordingsDirectoryUnavailable
    }

    init(config: AudioConfig = .default) {
        self.config = config
        self.ringBuffer = RingBuffer(capacity: config.bufferCapacity)
        self.lock = OSAllocatedUnfairLock(initialState: State())
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

        let file = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
        lock.withLock { $0.audioFile = file }
        ringBuffer.reset()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Feed ring buffer
            if let channelData = buffer.floatChannelData, buffer.format.channelCount > 0 {
                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                self.ringBuffer.write(samples)
            }

            // Snapshot shared state under lock
            let (file, bufferCallback, errorCallback) = self.lock.withLock { state in
                (state.audioFile, state.onAudioBuffer, state.onWriteError)
            }

            // Write WAV archive
            do {
                try file?.write(from: buffer)
            } catch {
                errorCallback?(error)
            }

            // Forward to subscribers (ASR engine)
            bufferCallback?(buffer)
        }

        try audioEngine.start()
        return fileURL
    }

    func stopCapture() -> URL? {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        let url = lock.withLock { state -> URL? in
            let fileURL = state.audioFile?.url
            state.audioFile = nil
            return fileURL
        }
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
