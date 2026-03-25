import Foundation
import UserNotifications
import os

extension Notification.Name {
    static let scheduledRecordingDidFire = Notification.Name("notetaker.scheduledRecordingDidFire")
}

/// Protocol for notification scheduling — enables testing without real `UNUserNotificationCenter`.
protocol SchedulerServiceProtocol: AnyObject, Sendable {
    func schedule(_ recording: ScheduledRecording)
    func cancel(_ recording: ScheduledRecording)
    func cancelAll()
    func requestAuthorization() async -> Bool
}

/// Manages `UNUserNotificationCenter` scheduling for timed recordings.
///
/// - Requests `.alert + .sound` authorization on first use.
/// - Schedules two notifications per `ScheduledRecording`: a reminder (N minutes before) and the start trigger.
/// - On receiving the `START_RECORDING` category action, posts `scheduledRecordingDidFire` with the recording's `UUID`.
/// - Follows the same pattern as `CrashLogService`: `nonisolated final class: NSObject, @unchecked Sendable`.
nonisolated final class SchedulerService: NSObject, SchedulerServiceProtocol, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "Scheduler")

    static let shared = SchedulerService()

    private static let categoryStart = "START_RECORDING"
    private static let categoryReminder = "REMINDER_RECORDING"

    private override init() {
        super.init()
    }

    // MARK: - Setup

    static func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared

        let startCategory = UNNotificationCategory(
            identifier: categoryStart,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let reminderCategory = UNNotificationCategory(
            identifier: categoryReminder,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([startCategory, reminderCategory])
        logger.info("SchedulerService installed as UNUserNotificationCenterDelegate")
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            Self.logger.info("Notification authorization granted: \(granted)")
            return granted
        } catch {
            Self.logger.error("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Schedule / Cancel

    /// Schedule reminder and start notifications for a `ScheduledRecording`.
    func schedule(_ recording: ScheduledRecording) {
        guard recording.isEnabled, let fireDate = recording.nextFireTime else {
            Self.logger.info("Skipping schedule for '\(recording.title)' — disabled or no future fire time")
            return
        }

        let center = UNUserNotificationCenter.current()
        let idStr = recording.id.uuidString

        // Reminder notification
        if recording.reminderMinutes > 0,
           let reminderDate = Calendar.current.date(
               byAdding: .minute,
               value: -recording.reminderMinutes,
               to: fireDate
           ),
           reminderDate > Date() {
            let reminderContent = UNMutableNotificationContent()
            reminderContent.title = "Recording starting soon"
            reminderContent.body = "\"\(recording.title)\" starts in \(recording.reminderMinutes) minute(s)"
            reminderContent.sound = .default
            reminderContent.categoryIdentifier = Self.categoryReminder

            let reminderComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: reminderDate
            )
            let reminderTrigger = UNCalendarNotificationTrigger(
                dateMatching: reminderComponents,
                repeats: false
            )
            let reminderRequest = UNNotificationRequest(
                identifier: "reminder-\(idStr)",
                content: reminderContent,
                trigger: reminderTrigger
            )
            center.add(reminderRequest) { error in
                if let error {
                    Self.logger.error("Failed to schedule reminder for '\(recording.title)': \(error.localizedDescription)")
                } else {
                    Self.logger.info("Reminder scheduled for '\(recording.title)' at \(reminderDate)")
                }
            }
        }

        // Start notification
        let startContent = UNMutableNotificationContent()
        startContent.title = "Recording started"
        startContent.body = "Now recording: \"\(recording.title)\""
        startContent.sound = .default
        startContent.categoryIdentifier = Self.categoryStart
        startContent.userInfo = ["recordingID": idStr]

        let startComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let startTrigger = UNCalendarNotificationTrigger(
            dateMatching: startComponents,
            repeats: false
        )
        let startRequest = UNNotificationRequest(
            identifier: "start-\(idStr)",
            content: startContent,
            trigger: startTrigger
        )
        center.add(startRequest) { error in
            if let error {
                Self.logger.error("Failed to schedule start for '\(recording.title)': \(error.localizedDescription)")
            } else {
                Self.logger.info("Start notification scheduled for '\(recording.title)' at \(fireDate)")
            }
        }
    }

    /// Remove pending notifications for a `ScheduledRecording`.
    func cancel(_ recording: ScheduledRecording) {
        let idStr = recording.id.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["start-\(idStr)", "reminder-\(idStr)"]
        )
        Self.logger.info("Cancelled notifications for '\(recording.title)'")
    }

    /// Remove all pending notification requests. Called before re-scheduling to prevent duplicates.
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        Self.logger.info("Cancelled all pending notifications")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.notification.request.content.categoryIdentifier == Self.categoryStart,
              let idString = response.notification.request.content.userInfo["recordingID"] as? String,
              let recordingID = UUID(uuidString: idString) else {
            return
        }

        Self.logger.info("START_RECORDING notification received for ID \(idString)")
        NotificationCenter.default.post(
            name: .scheduledRecordingDidFire,
            object: recordingID
        )
    }

    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
