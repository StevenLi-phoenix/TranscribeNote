import Foundation
import SwiftData
import Speech
import os

enum RecordingState {
    case idle
    case recording
    case stopping
    case completed
}

@Observable
final class ElapsedTimeClock {
    private(set) var elapsedTime: TimeInterval = 0
    var formatted: String { elapsedTime.hhmmss }
    func update(_ time: TimeInterval) { elapsedTime = time }
    func reset() { elapsedTime = 0 }
}

@Observable
final class AudioLevelMeter {
    private(set) var level: Float = 0
    func update(_ newLevel: Float) { level = newLevel }
    func reset() { level = 0 }
}

@Observable
final class RecordingViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "RecordingViewModel")

    private(set) var state: RecordingState = .idle
    private(set) var segments: [TranscriptSegment] = []
    private(set) var partialText: String = ""
    let clock = ElapsedTimeClock()
    let audioMeter = AudioLevelMeter()
    private(set) var errorMessage: String?
    private(set) var currentSession: RecordingSession?
    private(set) var summaries: [SummaryBlock] = []
    private(set) var isSummarizing: Bool = false
    private(set) var latestSummary: String?
    private(set) var summaryError: String?

    var isRecording: Bool { state == .recording }

    private let audioCaptureService: AudioCaptureService
    private let asrEngine: any ASREngine
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var drainTask: Task<Void, Never>?
    private var sessionPersisted = false
    private var summaryTimer: Timer?
    private var lastSummarizedSegmentCount: Int = 0
    private var summaryTask: Task<Void, Never>?
    private let summarizerService: SummarizerService
    private var summarizerConfig: SummarizerConfig
    private var llmConfig: LLMConfig
    private var nextPeriodicCoveringFrom: TimeInterval = 0
    private var periodicWindowCount: Int = 0
    init(
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        asrEngine: any ASREngine,
        summarizerService: SummarizerService = SummarizerService(engine: NoopLLMEngine()),
        summarizerConfig: SummarizerConfig = .default,
        llmConfig: LLMConfig = .default
    ) {
        self.audioCaptureService = audioCaptureService
        self.asrEngine = asrEngine
        self.summarizerService = summarizerService
        self.summarizerConfig = summarizerConfig
        self.llmConfig = llmConfig
        setupASRCallbacks()
    }

    convenience init(
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        llmConfig: LLMConfig = .default,
        summarizerConfig: SummarizerConfig = .default
    ) {
        let engine: any ASREngine
        do {
            engine = try SpeechAnalyzerEngine()
        } catch {
            Self.logger.warning("SpeechAnalyzerEngine unavailable (\(error.localizedDescription)), falling back to NoopASREngine")
            engine = NoopASREngine()
        }
        let llmEngine = LLMEngineFactory.create(from: llmConfig)
        let summarizer = SummarizerService(engine: llmEngine)
        self.init(
            audioCaptureService: audioCaptureService,
            asrEngine: engine,
            summarizerService: summarizer,
            summarizerConfig: summarizerConfig,
            llmConfig: llmConfig
        )
        if engine is NoopASREngine {
            self.errorMessage = "Speech recognition is unavailable. Transcription is disabled."
        }
    }

    deinit {
        timer?.invalidate()
        summaryTimer?.invalidate()
    }

    private func setupASRCallbacks() {
        asrEngine.onResult = { [weak self] result in
            await MainActor.run { [weak self] in
                self?.handleTranscriptResult(result)
            }
        }

        asrEngine.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func startRecording(modelContext: ModelContext? = nil) async {
        guard state == .idle || state == .completed else { return }
        if state == .completed {
            dismissCompletedRecording(modelContext: modelContext)
        }
        errorMessage = nil

        guard await checkPermissions() else { return }

        do {
            let fileURL = try startAudioPipeline()
            createSession(fileURL: fileURL)
            startElapsedTimer()
            startSummaryTimer()
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func checkPermissions() async -> Bool {
        let micGranted = await audioCaptureService.requestPermission()
        guard micGranted else {
            errorMessage = "Microphone permission denied"
            return false
        }

        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in
                    continuation.resume()
                }
            }
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            errorMessage = "Speech recognition permission denied"
            return false
        }
        return true
    }

    private func startAudioPipeline() throws -> URL {
        // 1. Wire up buffer forwarding BEFORE audio starts
        let engine = asrEngine
        audioCaptureService.onAudioBuffer = { buffer in
            engine.appendAudioBuffer(buffer)
        }

        // 2. Wire audio level metering (throttle on audio thread to avoid Task spam)
        let meter = audioMeter
        let lastLevel = OSAllocatedUnfairLock(initialState: Float(0))
        audioCaptureService.onAudioLevel = { level in
            let shouldUpdate = lastLevel.withLock { last -> Bool in
                guard abs(last - level) > 0.02 else { return false }
                last = level
                return true
            }
            if shouldUpdate {
                Task { @MainActor in
                    meter.update(level)
                }
            }
        }

        // 3. Start ASR (creates recognition request ready to receive buffers)
        try asrEngine.startRecognition(audioEngine: audioCaptureService.audioEngine)

        // 4. Start audio capture LAST (tap installed, engine starts, audio flows to ASR)
        return try audioCaptureService.startCapture()
    }

    private func createSession(fileURL: URL) {
        let session = RecordingSession(
            title: "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
        )
        session.audioFilePath = fileURL.lastPathComponent
        currentSession = session

        recordingStartTime = Date()
        state = .recording
        segments = []
        partialText = ""
        clock.reset()
    }

    private func startElapsedTimer() {
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.clock.update(Date().timeIntervalSince(start))
        }
        t.tolerance = 0.2
        timer = t
    }

    private func startSummaryTimer() {
        let interval = TimeInterval(summarizerConfig.intervalMinutes * 60)
        guard interval > 0 else { return }
        summaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.triggerPeriodicSummary()
        }
        summaryTimer?.tolerance = 5.0
    }

    func triggerPeriodicSummary() {
        guard state == .recording else { return }
        guard segments.count > lastSummarizedSegmentCount else { return }

        let unsummarized = Array(segments[lastSummarizedSegmentCount...])
        let previousSummary = self.latestSummary
        let config = self.summarizerConfig
        let llmCfg = self.llmConfig

        // Window-aligned boundaries: each timer fire = one window
        let intervalSeconds = TimeInterval(config.intervalMinutes * 60)
        let currentWindow = self.periodicWindowCount
        self.periodicWindowCount += 1
        let coveringFrom = self.nextPeriodicCoveringFrom
        let coveringTo = TimeInterval(currentWindow + 1) * intervalSeconds

        isSummarizing = true
        summaryError = nil

        summaryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await self.summarizerService.summarize(
                    segments: unsummarized,
                    previousSummary: previousSummary,
                    config: config,
                    llmConfig: llmCfg
                )
                guard !Task.isCancelled else { return }
                if !content.isEmpty {
                    let block = SummaryBlock(
                        coveringFrom: coveringFrom,
                        coveringTo: coveringTo,
                        content: content,
                        style: config.summaryStyle,
                        model: llmCfg.model
                    )
                    self.summaries.append(block)
                    self.latestSummary = content
                    self.lastSummarizedSegmentCount = self.segments.count
                    self.nextPeriodicCoveringFrom = coveringTo
                }
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("Periodic summary failed: \(error.localizedDescription)")
                self.summaryError = error.localizedDescription
            }
            self.isSummarizing = false
        }
    }

    func stopRecording(modelContext: ModelContext? = nil) {
        guard state == .recording else { return }

        timer?.invalidate()
        timer = nil
        summaryTimer?.invalidate()
        summaryTimer = nil
        // Don't cancel summaryTask — let in-flight LLM call finish; drainTask awaits it
        audioCaptureService.onAudioBuffer = nil
        audioCaptureService.onAudioLevel = nil
        audioMeter.reset()

        if let savedURL = audioCaptureService.stopCapture() {
            Self.logger.info("Audio saved to \(savedURL.path)")
        } else {
            Self.logger.warning("stopCapture returned nil — no audio file was saved")
        }

        if let session = currentSession {
            session.endedAt = Date()
        }

        // Show stopping UI while draining ASR results
        state = .stopping

        // Background: drain ASR results → persist to SwiftData → signal completed
        drainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.asrEngine.stopRecognition()
            guard !Task.isCancelled else { return }

            // Promote orphaned partialText to a final segment
            if !self.partialText.isEmpty {
                Self.logger.info("Promoting orphaned partialText (\(self.partialText.count) chars)")
                let segment = TranscriptSegment(
                    startTime: self.segments.last?.endTime ?? 0,
                    endTime: self.clock.elapsedTime,
                    text: self.partialText,
                    confidence: 0.0,
                    language: nil
                )
                self.segments.append(segment)
                self.partialText = ""
            }

            // Wait for any in-flight periodic summary to finish before persisting
            if let summaryTask = self.summaryTask {
                Self.logger.info("Awaiting in-flight periodic summary before persist...")
                await summaryTask.value
                self.summaryTask = nil
            }

            // Persist immediately — final summary runs on detail view after navigation
            self.persistSession(modelContext: modelContext)
            self.state = .completed
        }
    }

    /// Persist current session + segments to SwiftData. Idempotent — skips if already persisted.
    func persistSession(modelContext: ModelContext?) {
        guard !sessionPersisted, let modelContext, let session = currentSession else { return }
        sessionPersisted = true
        modelContext.insert(session)
        for segment in segments {
            segment.session = session
            modelContext.insert(segment)
        }
        for summary in summaries {
            summary.session = session
            modelContext.insert(summary)
        }
        do {
            try modelContext.save()
            Self.logger.info("Session saved with \(self.segments.count) segments, \(self.summaries.count) summaries")
        } catch {
            errorMessage = "Failed to save session: \(error.localizedDescription)"
        }
    }

    func dismissCompletedRecording(modelContext: ModelContext? = nil) {
        guard state == .completed else { return }
        // Persist whatever we have before dismissing
        if drainTask != nil, let modelContext {
            drainTask?.cancel()
            persistSession(modelContext: modelContext)
        }
        drainTask = nil
        state = .idle
        segments = []
        partialText = ""
        clock.reset()
        audioMeter.reset()
        currentSession = nil
        errorMessage = nil
        sessionPersisted = false
        summaries = []
        isSummarizing = false
        latestSummary = nil
        summaryError = nil
        lastSummarizedSegmentCount = 0
        nextPeriodicCoveringFrom = 0
        periodicWindowCount = 0
        summaryTask?.cancel()
        summaryTask = nil
    }

    func clearSummaryError() {
        summaryError = nil
    }

    func awaitDrainCompletion() async {
        await drainTask?.value
    }

    private func handleTranscriptResult(_ result: TranscriptResult) {
        if result.isFinal {
            // Dedup: skip if last committed segment has the exact same text
            if let last = segments.last, last.text == result.text {
                partialText = ""
                return
            }
            let segment = TranscriptSegment(
                startTime: result.startTime,
                endTime: result.endTime,
                text: result.text,
                confidence: result.confidence,
                language: result.language
            )
            segments.append(segment)
            partialText = ""
        } else {
            partialText = result.text
        }
    }
}
