import Foundation
import EventKit
import os

/// Reads system calendar events via EventKit and converts them to `ScheduledRecording` objects.
///
/// Uses `nonisolated final class` pattern (same as other services).
/// - Requires `com.apple.security.personal-information.calendars` entitlement.
/// - Requires `NSCalendarsUsageDescription` in Info.plist / build settings.
nonisolated final class CalendarService: @unchecked Sendable {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TranscribeNote", category: "Calendar")

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

        // 3b: Map recurrence rules from EKEvent
        let repeatRule = mapRecurrenceRule(event.recurrenceRules)

        // Map alarms to reminderMinutes (use first alarm's relative offset, or default 1)
        let reminderMinutes: Int
        if let alarm = event.alarms?.first {
            let offsetMinutes = Int(abs(alarm.relativeOffset) / 60)
            reminderMinutes = offsetMinutes > 0 ? offsetMinutes : 1
        } else {
            reminderMinutes = 1
        }

        return ScheduledRecording(
            title: event.title ?? "Untitled Meeting",
            label: event.calendar?.title ?? "",
            startTime: event.startDate,
            durationMinutes: durationMinutes,
            repeatRule: repeatRule,
            reminderMinutes: reminderMinutes,
            calendarEventIdentifier: event.eventIdentifier
        )
    }

    // MARK: - Recurrence Mapping (3b)

    /// Map EKRecurrenceRule to RepeatRule. Internal for testability.
    /// Uses stable EKKit API, NOT FoundationPreview Calendar.RecurrenceRule.
    func mapRecurrenceRule(_ rules: [EKRecurrenceRule]?) -> RepeatRule {
        guard let rule = rules?.first else { return .once }

        // Only map interval == 1 — "every 2 days" or "every 2 weeks" falls to .once
        guard rule.interval == 1 else {
            Self.logger.warning("Unsupported recurrence interval: \(rule.interval) for freq=\(rule.frequency.rawValue)")
            return .once
        }

        switch rule.frequency {
        case .daily:
            return .daily
        case .weekly:
            if let days = rule.daysOfTheWeek {
                let daySet = Set(days.map(\.dayOfTheWeek))
                let weekdaySet: Set<EKWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
                if daySet == weekdaySet {
                    return .weekdays
                }
            }
            return .weekly
        default:
            Self.logger.warning("Unsupported recurrence frequency: \(rule.frequency.rawValue)")
            return .once
        }
    }
}
