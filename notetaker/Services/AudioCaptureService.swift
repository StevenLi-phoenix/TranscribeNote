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
        var onAudioLevel: (@Sendable (Float) -> Void)?
        var onSilenceTimeout: (@Sendable () -> Void)?
        var vad: SimpleVAD?
    }

    /// External subscribers receive audio buffers (e.g., ASR engine).
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { lock.withLock { $0.onAudioBuffer } }
        set { lock.withLock { $0.onAudioBuffer = newValue } }
    }

    /// External subscribers receive audio level (0..1) for metering UI.
    var onAudioLevel: (@Sendable (Float) -> Void)? {
        get { lock.withLock { $0.onAudioLevel } }
        set { lock.withLock { $0.onAudioLevel = newValue } }
    }

    /// Fires when VAD detects sustained silence exceeding the timeout threshold.
    var onSilenceTimeout: (@Sendable () -> Void)? {
        get { lock.withLock { $0.onSilenceTimeout } }
        set { lock.withLock { $0.onSilenceTimeout = newValue } }
    }

    func configureVAD(_ vad: SimpleVAD?) {
        lock.withLock { $0.vad = vad }
    }

    enum AudioCaptureError: Error, LocalizedError {
        case recordingsDirectoryUnavailable
        case noInputDevice

        var errorDescription: String? {
            switch self {
            case .recordingsDirectoryUnavailable: "Recordings directory unavailable"
            case .noInputDevice: "No audio input device found.\nPlease connect a microphone to start recording."
            }
        }
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
        Self.logger.info("Input node format: \(inputFormat)")

        // Guard against no audio input device (e.g., Mac Mini with no built-in microphone)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Self.logger.error("No audio input device available (sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount))")
            throw AudioCaptureError.noInputDevice
        }

        // Verify a physical input device exists — format may report valid values
        // even when no hardware is connected (e.g., Mac Mini without microphone)
        if AVCaptureDevice.default(for: .audio) == nil {
            Self.logger.error("No audio capture device found")
            throw AudioCaptureError.noInputDevice
        }

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
                let (file, bufferCallback, levelCallback, silenceTimeoutCallback, vad) = self.lock.withLock { state in
                    (state.audioFile, state.onAudioBuffer, state.onAudioLevel, state.onSilenceTimeout, state.vad)
                }

                // Write audio archive
                do {
                    try file?.write(from: bufferCopy)
                } catch {
                    Self.logger.error("Audio file write failed: \(error.localizedDescription)")
                }

                // Calculate RMS audio level (used for metering UI and VAD)
                var level: Float = 0
                if let channelData = bufferCopy.floatChannelData {
                    let frameCount = Int(bufferCopy.frameLength)
                    if frameCount > 0 {
                        var sumOfSquares: Float = 0
                        let samples = channelData[0]
                        for i in 0..<frameCount {
                            let sample = samples[i]
                            sumOfSquares += sample * sample
                        }
                        let rms = sqrtf(sumOfSquares / Float(frameCount))
                        // Convert to 0..1 log scale: -50dB → 0, 0dB → 1
                        let db = 20 * log10f(max(rms, 1e-10))
                        level = max(0, min(1, (db + 50) / 50))
                        levelCallback?(level)
                    }
                }

                // VAD gating: decide whether to forward buffer to ASR
                let vadDecision = vad?.processLevel(level) ?? .forward
                if vadDecision == .silenceTimeout {
                    silenceTimeoutCallback?()
                }
                if vadDecision == .forward {
                    bufferCallback?(bufferCopy)
                }
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
            state.onAudioBuffer = nil
            state.onAudioLevel = nil
            state.onSilenceTimeout = nil
            state.vad = nil
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
        inputFormat: AVAudioFormat,
        baseName: String = UUID().uuidString
    ) throws -> (AVAudioFile, URL) {

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
