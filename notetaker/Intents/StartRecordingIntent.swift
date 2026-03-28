import AppIntents
import SwiftData
import os

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start a new recording session in Notetaker")
    static var openAppWhenRun = true  // App must be running for audio capture

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "StartRecordingIntent")

    @Parameter(title: "Title")
    var sessionTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start recording with title \(\.$sessionTitle)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.logger.info("StartRecordingIntent triggered, title=\(sessionTitle ?? "<none>")")
        try AppIntentState.shared.ensureReady()
        guard let vm = AppIntentState.shared.viewModel,
              let container = AppIntentState.shared.modelContainerRef else {
            throw AppIntentError.appNotRunning
        }

        guard vm.state == .idle || vm.state == .completed else {
            Self.logger.warning("Cannot start — already recording (state=\(String(describing: vm.state)))")
            return .result(dialog: "Recording is already in progress")
        }

        await vm.startRecording(modelContext: container.mainContext)

        if let title = sessionTitle, !title.isEmpty, let session = vm.currentSession {
            session.title = title
        }

        Self.logger.info("Recording started via App Intent")
        return .result(dialog: "Recording started")
    }
}
