import Foundation
import Intents
import os

/// Checks macOS Focus / Do Not Disturb status and provides recording-time reminders.
nonisolated enum FocusModeService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "FocusModeService")

    enum FocusStatus: Sendable {
        case enabled    // Focus/DND is active
        case disabled   // No Focus active
        case unknown    // Can't determine (authorization denied or unavailable)
    }

    /// Check if Focus / Do Not Disturb is currently enabled.
    /// Uses INFocusStatusCenter which requires Intents framework.
    static func currentStatus() -> FocusStatus {
        let center = INFocusStatusCenter.default
        let status = center.focusStatus

        switch status.isFocused {
        case .some(true):
            logger.debug("Focus mode is enabled")
            return .enabled
        case .some(false):
            logger.debug("Focus mode is disabled")
            return .disabled
        case .none:
            logger.debug("Focus status unknown")
            return .unknown
        }
    }

    /// Request authorization to read Focus status.
    static func requestAuthorization() async -> Bool {
        let center = INFocusStatusCenter.default
        let status = center.focusStatus
        let canRead = status.isFocused != nil
        logger.info("Focus status authorization check: canRead=\(canRead)")
        return canRead
    }

    /// Whether the user has enabled focus reminders in settings.
    static var isReminderEnabled: Bool {
        UserDefaults.standard.object(forKey: "focusReminderEnabled") as? Bool ?? true
    }

    /// Check if we should show a focus reminder (Focus not active + reminders enabled).
    static func shouldShowReminder() -> Bool {
        guard isReminderEnabled else { return false }
        let status = currentStatus()
        return status == .disabled
    }
}
