import Foundation
import SwiftData
import Speech
import os

enum RecordingState {
    case idle
    case recording
    case stopping
}

@Observable
final class RecordingViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "RecordingViewModel")

    private(set) var state: RecordingState = .idle
    private(set) var segments: [TranscriptSegment] = []
    private(set) var partialText: String = ""
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var errorMessage: String?
    private(set) var currentSession: RecordingSession?

    var isRecording: Bool { state == .recording }

    var formattedElapsedTime: String {
        elapsedTime.hhmmss
    }

    private let audioCaptureService: AudioCaptureService
    private let asrEngine: any ASREngine
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var audioFileURL: URL?

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
            Task { @MainActor [weak self] in
                self?.handleTranscriptResult(result)
            }
        }

        asrEngine.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func startRecording() async {
        guard state == .idle else { return }
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
        self.audioFileURL = fileURL

        let session = RecordingSession(
            title: "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
        )
        session.audioFilePath = fileURL.lastPathComponent
        currentSession = session

        recordingStartTime = Date()
        state = .recording
        segments = []
        partialText = ""
        elapsedTime = 0
    }

    private func startElapsedTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
    }

    func stopRecording(modelContext: ModelContext? = nil) {
        guard state == .recording else { return }
        state = .stopping

        timer?.invalidate()
        timer = nil

        asrEngine.stopRecognition()
        audioCaptureService.onAudioBuffer = nil

        if let savedURL = audioCaptureService.stopCapture() {
            Self.logger.info("Audio saved to \(savedURL.path)")
        } else {
            Self.logger.warning("stopCapture returned nil — no audio file was saved")
        }

        if let session = currentSession {
            session.endedAt = Date()

            if let modelContext {
                modelContext.insert(session)
                for segment in segments {
                    segment.session = session
                    modelContext.insert(segment)
                }
                do {
                    try modelContext.save()
                } catch {
                    self.errorMessage = "Failed to save session: \(error.localizedDescription)"
                }
            }
        }

        state = .idle
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
