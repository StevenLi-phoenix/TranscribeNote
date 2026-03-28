import SwiftUI
import SwiftData
import os

/// Bridge for App Intents to access the running app's state.
@MainActor
final class AppIntentState {
    static let shared = AppIntentState()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "AppIntentState")

    weak var viewModel: RecordingViewModel?
    var modelContainerRef: ModelContainer?

    private init() {}

    func ensureReady() throws {
        guard viewModel != nil, modelContainerRef != nil else {
            Self.logger.error("AppIntentState not configured — app may not be running")
            throw AppIntentError.appNotRunning
        }
    }
}

enum AppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotRunning
    case noActiveRecording
    case noSessionFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotRunning: "Notetaker is not running"
        case .noActiveRecording: "No active recording"
        case .noSessionFound: "No session found"
        }
    }
}
