import UserNotifications
import os

/// Schedules weekly digest notifications via UNUserNotificationCenter.
nonisolated enum InsightNotificationService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "InsightNotificationService")

    static let weeklyDigestIdentifier = "com.notetaker.weeklyDigest"

    /// Request notification permission.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification permission: \(granted)")
            return granted
        } catch {
            logger.error("Notification permission error: \(error.localizedDescription)")
            return false
        }
    }

    /// Schedule a weekly digest notification for Monday at 9:00 AM.
    static func scheduleWeeklyDigest(body: String) {
        let center = UNUserNotificationCenter.current()

        // Remove existing
        center.removePendingNotificationRequests(withIdentifiers: [weeklyDigestIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Weekly Meeting Digest"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_DIGEST"

        // Every Monday at 9:00 AM
        var dateComponents = DateComponents()
        dateComponents.weekday = 2  // Monday
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyDigestIdentifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                logger.error("Failed to schedule weekly digest: \(error.localizedDescription)")
            } else {
                logger.info("Weekly digest notification scheduled for Monday 9:00 AM")
            }
        }
    }

    /// Cancel weekly digest notifications.
    static func cancelWeeklyDigest() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyDigestIdentifier])
        logger.info("Weekly digest notification cancelled")
    }

    /// Check if weekly digest is currently scheduled.
    static func isScheduled() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        return pending.contains { $0.identifier == weeklyDigestIdentifier }
    }
}
