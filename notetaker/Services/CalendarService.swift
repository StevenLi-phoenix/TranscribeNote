import Foundation
import EventKit
import os

/// Reads system calendar events via EventKit and converts them to `ScheduledRecording` objects.
///
/// Uses `nonisolated final class` pattern (same as other services).
/// - Requires `com.apple.security.personal-information.calendars` entitlement.
/// - Requires `NSCalendarsUsageDescription` in Info.plist / build settings.
nonisolated final class CalendarService: @unchecked Sendable {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "Calendar")

    private let store = EKEventStore()

    // MARK: - Authorization

    /// Request full calendar read access (macOS 14+).
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            Self.logger.info("Calendar access granted: \(granted)")
            return granted
        } catch {
            Self.logger.error("Calendar access error: \(error.localizedDescription)")
            return false
        }
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Fetch

    /// Return calendar events starting within the next `hours` hours, sorted by start date.
    func fetchUpcomingMeetings(within hours: Int = 24) async -> [EKEvent] {
        guard authorizationStatus == .fullAccess else {
            Self.logger.warning("Calendar access not granted — returning empty event list")
            return []
        }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        Self.logger.info("Fetched \(events.count) upcoming meeting(s) in next \(hours)h")
        return events
    }

    // MARK: - Convert

    /// Map an `EKEvent` to a `ScheduledRecording` (not yet persisted).
    func importAsScheduledRecording(_ event: EKEvent) -> ScheduledRecording {
        let durationMinutes: Int?
        if let end = event.endDate {
            let seconds = end.timeIntervalSince(event.startDate)
            durationMinutes = seconds > 0 ? Int(seconds / 60) : nil
        } else {
            durationMinutes = nil
        }

        return ScheduledRecording(
            title: event.title ?? "Untitled Meeting",
            label: event.calendar?.title ?? "",
            startTime: event.startDate,
            durationMinutes: durationMinutes,
            repeatRule: .once,
            reminderMinutes: 1
        )
    }
}
