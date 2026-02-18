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
final class RecordingViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "RecordingViewModel")

    private(set) var state: RecordingState = .idle
    private(set) var segments: [TranscriptSegment] = []
    private(set) var partialText: String = ""
    let clock = ElapsedTimeClock()
    private(set) var errorMessage: String?
    private(set) var currentSession: RecordingSession?

    var isRecording: Bool { state == .recording }

    private let audioCaptureService: AudioCaptureService
    private let asrEngine: any ASREngine
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var drainTask: Task<Void, Never>?
    private var sessionPersisted = false
    init(
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        asrEngine: any ASREngine
    ) {
        self.audioCaptureService = audioCaptureService
        self.asrEngine = asrEngine
        setupASRCallbacks()
    }

    convenience init(
        audioCaptureService: AudioCaptureService = AudioCaptureService()
    ) {
        let engine: any ASREngine
        do {
            engine = try SpeechAnalyzerEngine()
        } catch {
            Self.logger.warning("SpeechAnalyzerEngine unavailable (\(error.localizedDescription)), falling back to NoopASREngine")
            engine = NoopASREngine()
        }
        self.init(audioCaptureService: audioCaptureService, asrEngine: engine)
        if engine is NoopASREngine {
            self.errorMessage = "Speech recognition is unavailable. Transcription is disabled."
        }
    }

    deinit {
        timer?.invalidate()
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

        // 2. Start ASR (creates recognition request ready to receive buffers)
        try asrEngine.startRecognition(audioEngine: audioCaptureService.audioEngine)

        // 3. Start audio capture LAST (tap installed, engine starts, audio flows to ASR)
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

    func stopRecording(modelContext: ModelContext? = nil) {
        guard state == .recording else { return }

        timer?.invalidate()
        timer = nil
        audioCaptureService.onAudioBuffer = nil

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
        do {
            try modelContext.save()
            Self.logger.info("Session saved with \(self.segments.count) segments")
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
        currentSession = nil
        errorMessage = nil
        sessionPersisted = false
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
