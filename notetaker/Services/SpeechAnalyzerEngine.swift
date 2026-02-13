import Foundation
@preconcurrency import AVFoundation
import Speech
import CoreMedia

nonisolated final class SpeechAnalyzerEngine: @unchecked Sendable {
    enum EngineError: Error {
        case speechAnalyzerUnavailable
    }

    var onResult: (@Sendable (TranscriptResult) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let transcriber: SpeechTranscriber
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
        self.transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
    }
}

extension SpeechAnalyzerEngine: ASREngine {
    nonisolated var supportsOnDevice: Bool { true }

    nonisolated func startRecognition(audioEngine: AVAudioEngine) throws {
        queue.sync {
            stopRecognitionLocked()

            let sourceFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation

            let speechAnalyzer = SpeechAnalyzer(modules: [transcriber])
            analyzer = speechAnalyzer

            let transcriber = self.transcriber
            let locale = self.locale.identifier

            // Task 1: Set up format conversion and start analyzer
            analyzerTask = Task.detached { [weak self] in
                guard let self else { return }

                do {
                    guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber]
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
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { break }

                        let text = String(result.text.characters)
                        guard !text.isEmpty else { continue }

                        let (startTime, endTime) = self.extractTimeRange(from: result.text)

                        let transcriptResult = TranscriptResult(
                            text: text,
                            startTime: startTime,
                            endTime: endTime,
                            confidence: 1.0,
                            language: locale,
                            isFinal: result.isFinal
                        )
                        self.onResult?(transcriptResult)
                    }
                } catch {
                    if !Task.isCancelled {
                        self.onError?(error)
                    }
                }
            }
        }
    }

    nonisolated func stopRecognition() {
        queue.sync {
            stopRecognitionLocked()
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

    /// Must be called while holding `queue`.
    private func stopRecognitionLocked() {
        inputContinuation?.finish()
        inputContinuation = nil

        analyzerTask?.cancel()
        analyzerTask = nil

        resultTask?.cancel()
        resultTask = nil

        analyzer = nil
        converter = nil
        analyzerFormat = nil
        isReady = false
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
