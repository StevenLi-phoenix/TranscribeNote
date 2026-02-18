import AVFoundation
import os

nonisolated final class AudioCaptureService: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "AudioCapture")

    private(set) var audioEngine = AVAudioEngine()
    private let ringBuffer: RingBuffer
    private let config: AudioConfig
    private let lock: OSAllocatedUnfairLock<State>
    private let writeQueue = DispatchQueue(label: "com.notetaker.audio-file-writer", qos: .userInitiated)

    private struct State: Sendable {
        var audioFile: AVAudioFile?
        var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    }

    /// External subscribers receive audio buffers (e.g., ASR engine).
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { lock.withLock { $0.onAudioBuffer } }
        set { lock.withLock { $0.onAudioBuffer = newValue } }
    }

    enum AudioCaptureError: Error {
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

    /// Start capture. Returns the audio file URL for archival.
    func startCapture() throws -> URL {
        let recordingsDir = try Self.recordingsDirectory()
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let (file, fileURL) = try Self.createAudioFile(in: recordingsDir, inputFormat: inputFormat)
        lock.withLock { $0.audioFile = file }
        ringBuffer.reset()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Feed ring buffer (pointer-based — stays on audio thread, no Array allocation)
            if let channelData = buffer.floatChannelData, buffer.format.channelCount > 0 {
                let frameCount = Int(buffer.frameLength)
                self.ringBuffer.write(channelData[0], count: frameCount)
            }

            // Deep-copy buffer so the original can be recycled by the audio engine
            guard let bufferCopy = Self.copyBuffer(buffer) else {
                Self.logger.error("Failed to deep-copy audio buffer")
                return
            }

            // Offload file I/O and ASR forwarding to background queue
            self.writeQueue.async {
                // Snapshot shared state under lock
                let (file, bufferCallback) = self.lock.withLock { state in
                    (state.audioFile, state.onAudioBuffer)
                }

                // Write audio archive
                do {
                    try file?.write(from: bufferCopy)
                } catch {
                    Self.logger.error("Audio file write failed: \(error.localizedDescription)")
                }

                // Forward to subscribers (ASR engine)
                bufferCallback?(bufferCopy)
            }
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
        if let url {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            Self.logger.info("Recording saved: \(url.lastPathComponent) (\(fileSize) bytes)")
        }
        return url
    }

    /// Deep-copy an AVAudioPCMBuffer so the original can be reused by the audio engine.
    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return nil }
        copy.frameLength = buffer.frameLength
        let channelCount = Int(buffer.format.channelCount)
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    /// Create an audio file for recording. Tries M4A/AAC first, falls back to WAV.
    private static func createAudioFile(
        in directory: URL,
        inputFormat: AVAudioFormat
    ) throws -> (AVAudioFile, URL) {
        let baseName = UUID().uuidString

        // Try M4A/AAC first
        let m4aURL = directory.appendingPathComponent("\(baseName).m4a")
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let file = try AVAudioFile(
                forWriting: m4aURL,
                settings: aacSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            logger.info("Recording format: M4A/AAC at \(Int(inputFormat.sampleRate))Hz")
            return (file, m4aURL)
        } catch {
            logger.warning("M4A/AAC creation failed (\(error.localizedDescription)), falling back to WAV")
        }

        // Fall back to WAV
        let wavURL = directory.appendingPathComponent("\(baseName).wav")
        let file = try AVAudioFile(forWriting: wavURL, settings: inputFormat.settings)
        logger.info("Recording format: WAV at \(Int(inputFormat.sampleRate))Hz")
        return (file, wavURL)
    }

    static func recordingsDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AudioCaptureError.recordingsDirectoryUnavailable
        }
        return appSupport.appendingPathComponent("notetaker/Recordings", isDirectory: true)
    }
}
