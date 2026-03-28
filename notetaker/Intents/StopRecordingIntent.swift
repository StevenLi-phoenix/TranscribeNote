import AppIntents
import SwiftData
import os

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stop the current recording and save it")

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "StopRecordingIntent")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.logger.info("StopRecordingIntent triggered")
        try AppIntentState.shared.ensureReady()
        guard let vm = AppIntentState.shared.viewModel,
              let container = AppIntentState.shared.modelContainerRef else {
            throw AppIntentError.appNotRunning
        }

        guard vm.isActive else {
            Self.logger.warning("No active recording to stop")
            throw AppIntentError.noActiveRecording
        }

        vm.stopRecording(modelContext: container.mainContext)

        Self.logger.info("Recording stopped via App Intent")
        return .result(dialog: "Recording stopped and saved")
    }
}
