import AVFoundation

/// Plays an audio file through AVAudioEngine in offline (manual) rendering mode
/// and delivers PCM buffers via callback.
///
/// Uses `enableManualRenderingMode(.offline, ...)` so that no audio hardware is
/// required — suitable for headless xcodebuild test environments.
nonisolated final class FileAudioSource: @unchecked Sendable {

    private let lock = NSLock()

    private var _bufferCount = 0
    var bufferCount: Int { lock.withLock { _bufferCount } }

    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onFinished: (() -> Void)?

    private var _processingFormat: AVAudioFormat?
    var processingFormat: AVAudioFormat? { lock.withLock { _processingFormat } }

    /// Rendering thread handle so `stop()` can cancel early.
    private var renderThread: Thread?
    private var _cancelled = false

    func start(url: URL, bufferSize: AVAudioFrameCount = 1024) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)

        lock.withLock {
            _processingFormat = format
            _cancelled = false
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        // Enable offline manual rendering — no audio hardware needed.
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: bufferSize
        )

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)

        try engine.start()
        player.play()
        player.scheduleFile(file, at: nil)

        // Drive the rendering loop on a background thread so `start` returns
        // immediately (matching the original real-time API contract).
        let thread = Thread { [weak self] in
            self?.renderLoop(
                engine: engine,
                player: player,
                format: format,
                totalFrames: totalFrames,
                bufferSize: bufferSize
            )
        }
        thread.qualityOfService = .userInitiated
        lock.withLock { renderThread = thread }
        thread.start()
    }

    func stop() {
        lock.withLock { _cancelled = true }
    }

    // MARK: - Private

    private func renderLoop(
        engine: AVAudioEngine,
        player: AVAudioPlayerNode,
        format: AVAudioFormat,
        totalFrames: AVAudioFrameCount,
        bufferSize: AVAudioFrameCount
    ) {
        var framesRendered: AVAudioFrameCount = 0

        while framesRendered < totalFrames {
            let cancelled = lock.withLock { _cancelled }
            if cancelled { break }

            let framesToRender = min(bufferSize, totalFrames - framesRendered)

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesToRender
            ) else { break }

            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(framesToRender, to: outputBuffer)
            } catch {
                break
            }

            switch status {
            case .success:
                framesRendered += outputBuffer.frameLength
                lock.withLock { _bufferCount += 1 }
                onAudioBuffer?(outputBuffer)

            case .insufficientDataFromInputNode:
                // Player has been drained; treat as end-of-file.
                break

            case .cannotDoInCurrentContext:
                // Transient issue — retry.
                continue

            case .error:
                break

            @unknown default:
                break
            }

            // Break out of the while loop on terminal statuses.
            if status == .insufficientDataFromInputNode || status == .error {
                break
            }
        }

        player.stop()
        engine.stop()

        let cancelled = lock.withLock { _cancelled }
        if !cancelled {
            onFinished?()
        }

        lock.withLock { renderThread = nil }
    }
}
