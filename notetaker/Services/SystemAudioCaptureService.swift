import ScreenCaptureKit
import AVFoundation
import os

/// Audio source selection for recording.
enum AudioSource: String, CaseIterable, Sendable {
    case microphone = "microphone"
    case systemAudio = "systemAudio"
    case both = "both"

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        case .both: return "Both"
        }
    }
}

/// Captures system audio output via ScreenCaptureKit (Zoom, Meet, Teams, etc.).
///
/// Unlike `AudioCaptureService` (which uses `AVAudioEngine` input tap for mic),
/// this service uses `SCStream` to capture system audio output — audio from other apps.
/// Requires Screen Recording permission (macOS TCC).
nonisolated final class SystemAudioCaptureService: NSObject, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "SystemAudioCaptureService"
    )

    // State protected by lock
    private struct State {
        var stream: SCStream?
        var isCapturing = false
        var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
        var onAudioLevel: (@Sendable (Float) -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let captureQueue = DispatchQueue(
        label: "com.notetaker.systemAudioCapture",
        qos: .userInteractive
    )

    /// Check if Screen Recording permission is available.
    /// Note: There's no direct API to check — we try to enumerate content.
    static func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            logger.warning("Screen Recording permission not granted: \(error.localizedDescription)")
            return false
        }
    }

    /// Start capturing system audio.
    func startCapture(
        sampleRate: Double = 16000,
        channelCount: Int = 1,
        onAudioBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onAudioLevel: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        let alreadyCapturing = state.withLock { $0.isCapturing }
        guard !alreadyCapturing else {
            throw SystemAudioError.captureAlreadyRunning
        }

        Self.logger.info("Starting system audio capture at \(sampleRate)Hz")

        // Get shareable content to create filter
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        // We need at least one display to create a content filter for audio-only capture
        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplayAvailable
        }

        // Create filter that captures the entire display (we only want audio)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure for audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = channelCount

        // Minimize video overhead since we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        // Add audio output
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)

        state.withLock {
            $0.onAudioBuffer = onAudioBuffer
            $0.onAudioLevel = onAudioLevel
            $0.stream = stream
        }

        try await stream.startCapture()

        state.withLock { $0.isCapturing = true }
        Self.logger.info("System audio capture started successfully")
    }

    /// Stop capturing system audio.
    func stopCapture() async {
        let stream = state.withLock { s -> SCStream? in
            s.isCapturing = false
            s.onAudioBuffer = nil
            s.onAudioLevel = nil
            let stream = s.stream
            s.stream = nil
            return stream
        }

        if let stream {
            do {
                try await stream.stopCapture()
                Self.logger.info("System audio capture stopped")
            } catch {
                Self.logger.error("Error stopping system audio capture: \(error.localizedDescription)")
            }
        }
    }

    var isCapturing: Bool {
        state.withLock { $0.isCapturing }
    }

    // MARK: - Error Types

    enum SystemAudioError: Error, LocalizedError {
        case noDisplayAvailable
        case permissionDenied
        case captureAlreadyRunning

        var errorDescription: String? {
            switch self {
            case .noDisplayAvailable:
                return "No display available for audio capture"
            case .permissionDenied:
                return "Screen Recording permission is required for system audio capture"
            case .captureAlreadyRunning:
                return "System audio capture is already running"
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension SystemAudioCaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Self.logger.error("System audio stream stopped with error: \(error.localizedDescription)")
        state.withLock {
            $0.isCapturing = false
            $0.stream = nil
        }
    }
}

// MARK: - SCStreamOutput

extension SystemAudioCaptureService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        guard let format = AVAudioFormat(streamDescription: asbd),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            return
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy audio data from CMBlockBuffer to AVAudioPCMBuffer
        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &dataLength, dataPointerOut: &dataPointer
        )

        guard let dataPointer else { return }

        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
           let destPointer = pcmBuffer.floatChannelData?[0] {
            // Float32 format — direct copy
            let bytesToCopy = min(dataLength, Int(frameCount) * MemoryLayout<Float>.size)
            memcpy(destPointer, dataPointer, bytesToCopy)
        } else if asbd.pointee.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
                  asbd.pointee.mBitsPerChannel == 16,
                  let destPointer = pcmBuffer.int16ChannelData?[0] {
            // Int16 format — direct copy
            let bytesToCopy = min(dataLength, Int(frameCount) * MemoryLayout<Int16>.size)
            memcpy(destPointer, dataPointer, bytesToCopy)
        } else {
            Self.logger.warning("Unsupported audio format flags: \(asbd.pointee.mFormatFlags)")
            return
        }

        // Calculate audio level for metering
        if let channelData = pcmBuffer.floatChannelData?[0] {
            var sum: Float = 0
            let count = Int(pcmBuffer.frameLength)
            for i in 0..<count {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / max(1, Float(count)))
            // Convert to 0-1 scale (log scale, -50dB to 0dB)
            let db = 20 * log10(max(rms, 1e-7))
            let level = max(0, min(1, (db + 50) / 50))

            state.withLock { $0.onAudioLevel?(level) }
        }

        // Forward buffer to consumer (ASR engine)
        state.withLock { $0.onAudioBuffer?(pcmBuffer) }
    }
}
