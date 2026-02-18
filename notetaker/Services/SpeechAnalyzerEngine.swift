@preconcurrency import AVFoundation
import Speech
import CoreMedia
import os

nonisolated final class SpeechAnalyzerEngine: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.notetaker", category: "SpeechAnalyzerEngine")

    enum EngineError: Error {
        case speechAnalyzerUnavailable
    }

    private var _onResult: (@Sendable (TranscriptResult) async -> Void)?
    private var _onError: (@Sendable (Error) -> Void)?
    private var sessionID: UUID?

    var onResult: (@Sendable (TranscriptResult) async -> Void)? {
        get { queue.sync { _onResult } }
        set { queue.sync { _onResult = newValue } }
    }

    var onError: (@Sendable (Error) -> Void)? {
        get { queue.sync { _onError } }
        set { queue.sync { _onError = newValue } }
    }

    /// Per-session transcriber — created fresh in `startRecognition()`, nilled in `stopRecognitionLocked()`.
    private var transcriber: SpeechTranscriber?
    private let locale: Locale

    /// Serial queue protecting all mutable state.
    private let queue = DispatchQueue(label: "com.notetaker.speech-analyzer-engine")

    // Mutable state (queue-protected)
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var isReady = false
    private var analyzerTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?

    init(locale: Locale = .current) throws {
        self.locale = locale
        // Validate SpeechTranscriber can be created with this locale (fail-fast).
        // The instance is intentionally discarded — a fresh one is created per session.
        _ = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        Self.log.info("Engine initialized for locale \(locale.identifier)")
    }

    /// Creates a fresh `SpeechTranscriber` for a new recognition session.
    private func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
    }
}

extension SpeechAnalyzerEngine: ASREngine {
    nonisolated func startRecognition(audioEngine: AVAudioEngine) throws {
        queue.sync {
            stopRecognitionLocked()

            // Fresh transcriber per session — SpeechTranscriber is single-use.
            let newSessionID = UUID()
            self.sessionID = newSessionID
            let sessionTranscriber = makeTranscriber()
            self.transcriber = sessionTranscriber
            Self.log.info("Created new SpeechTranscriber for session \(newSessionID.uuidString)")

            let sourceFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation

            let speechAnalyzer = SpeechAnalyzer(modules: [sessionTranscriber])
            analyzer = speechAnalyzer

            let locale = self.locale.identifier

            // Task 1: Set up format conversion and start analyzer
            analyzerTask = Task.detached { [weak self] in
                guard let self else { return }

                do {
                    guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [sessionTranscriber]
                    ) else {
                        self.onError?(EngineError.speechAnalyzerUnavailable)
                        return
                    }

                    guard !Task.isCancelled else { return }

                    self.queue.sync {
                        self.analyzerFormat = targetFormat
                        if sourceFormat != targetFormat {
                            self.converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
                        }
                        self.isReady = true
                    }

                    guard !Task.isCancelled else { return }
                    try await speechAnalyzer.start(inputSequence: stream)
                } catch {
                    if !Task.isCancelled {
                        self.onError?(error)
                    }
                }
            }

            // Task 2: Iterate transcriber results and emit TranscriptResults
            resultTask = Task.detached { [weak self] in
                guard let self else { return }

                do {
                    for try await result in sessionTranscriber.results {
                        guard !Task.isCancelled else { break }

                        let text = String(result.text.characters)
                        guard !text.isEmpty else { continue }

                        let (startTime, endTime) = self.extractTimeRange(from: result.text)

                        // SpeechTranscriber does not expose per-segment confidence
                        let transcriptResult = TranscriptResult(
                            text: text,
                            startTime: startTime,
                            endTime: endTime,
                            confidence: 0.0,
                            language: locale,
                            isFinal: result.isFinal
                        )
                        // await ensures callback fully completes before loop continues
                        await self.onResult?(transcriptResult)
                    }
                    Self.log.info("Result loop ended naturally")
                } catch {
                    if !Task.isCancelled {
                        self.onError?(error)
                    }
                }
            }
        }
    }

    nonisolated func stopRecognition() async {
        // Phase 1: Finish input stream, capture references
        let (capturedAnalyzer, capturedResultTask, currentSessionID) = queue.sync { () -> (SpeechAnalyzer?, Task<Void, Never>?, UUID?) in
            Self.log.info("stopRecognition Phase 1: finishing input")
            inputContinuation?.finish()
            inputContinuation = nil

            let analyzer = self.analyzer
            let task = resultTask
            resultTask = nil
            let sid = sessionID
            return (analyzer, task, sid)
        }

        // Phase 2: Finalize analyzer — processes remaining audio, converts volatile→final,
        // terminates transcriber.results stream. This is the key Apple API call.
        // Without this, the results stream never terminates and drain hangs forever.
        if let capturedAnalyzer {
            Self.log.info("stopRecognition Phase 2: finalizing analyzer")
            try? await capturedAnalyzer.finalizeAndFinishThroughEndOfInput()
            Self.log.info("stopRecognition Phase 2: analyzer finalized")
        }

        // Phase 3: Drain resultTask (should complete quickly after finalize).
        // Timeout is safety net only — normal path completes fast.
        if let capturedResultTask {
            Self.log.info("stopRecognition Phase 3: draining results")
            await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                let handles = OSAllocatedUnfairLock<(drain: Task<Void, Never>?, timeout: Task<Void, Never>?)>(initialState: (nil, nil))

                let drainHandle = Task {
                    await capturedResultTask.value
                    if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                        handles.withLock { $0.timeout?.cancel() }
                        continuation.resume()
                    }
                }
                handles.withLock { $0.drain = drainHandle }

                let timeoutHandle = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                        handles.withLock { $0.drain?.cancel() }
                        Self.log.warning("stopRecognition Phase 3: drain timed out")
                        continuation.resume()
                    }
                }
                handles.withLock { $0.timeout = timeoutHandle }
            }
            Self.log.info("stopRecognition Phase 3: drain complete")
        }

        // Phase 4: Clean up remaining state (only if session hasn't changed)
        queue.sync {
            guard sessionID == currentSessionID else {
                Self.log.info("stopRecognition Phase 4: skipped — session changed")
                return
            }
            Self.log.info("stopRecognition Phase 4: cleaning up")
            analyzerTask?.cancel()
            analyzerTask = nil
            analyzer = nil
            transcriber = nil
            converter = nil
            analyzerFormat = nil
            isReady = false
            sessionID = nil
        }
    }

    nonisolated func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.sync {
            guard isReady, let continuation = inputContinuation else { return }

            if let converter {
                guard let convertedBuffer = convertBuffer(buffer, using: converter) else { return }
                continuation.yield(AnalyzerInput(buffer: convertedBuffer))
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }
    }

    // MARK: - Private

    /// Must be called while holding `queue`. Aggressive force-stop used by `startRecognition()` to clean up prior session.
    private func stopRecognitionLocked() {
        inputContinuation?.finish()
        inputContinuation = nil

        analyzerTask?.cancel()
        analyzerTask = nil

        resultTask?.cancel()
        resultTask = nil

        analyzer = nil
        transcriber = nil
        converter = nil
        analyzerFormat = nil
        isReady = false
        sessionID = nil
        Self.log.info("Session force-stopped, transcriber released")
    }

    /// Extract the full audio time span from all attributed runs.
    private func extractTimeRange(from text: AttributedString) -> (start: TimeInterval, end: TimeInterval) {
        var minStart: Double = .infinity
        var maxEnd: Double = -.infinity
        for run in text.runs {
            if let timeRange = run.audioTimeRange {
                let s = CMTimeGetSeconds(timeRange.start)
                let e = CMTimeGetSeconds(timeRange.end)
                if s.isFinite { minStart = min(minStart, s) }
                if e.isFinite { maxEnd = max(maxEnd, e) }
            }
        }
        if minStart.isFinite && maxEnd.isFinite {
            return (minStart, maxEnd)
        }
        return (0, 0)
    }

    /// Convert an audio buffer to the analyzer's expected format.
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard let targetFormat = analyzerFormat else { return nil }

        let sampleRateRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var hasProvided = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        if error != nil { return nil }
        return outputBuffer
    }
}
