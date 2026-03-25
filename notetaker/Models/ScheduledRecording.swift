import Foundation
import SwiftData

/// A user-created or calendar-imported recording schedule.
///
/// - `repeatRule` stored as `String` raw value (SwiftData can't store custom enums directly).
/// - `label` used for grouping in `ScheduleView` (e.g. "2026 spring class" or calendar name).
/// - `lastTriggeredAt` updated on each firing; used by `SchedulerService` to re-schedule repeating tasks.
/// - All properties have inline defaults so SwiftData lightweight migration fills existing rows correctly.
@Model
final class ScheduledRecording {
    var id: UUID = UUID()
    var title: String = ""
    var label: String = ""
    var startTime: Date = Date()
    var durationMinutes: Int? = nil
    var repeatRule: String = RepeatRule.once.rawValue
    var reminderMinutes: Int = 1
    var isEnabled: Bool = true
    var lastTriggeredAt: Date? = nil
    /// EKEvent.eventIdentifier for robust calendar dedup.
    var calendarEventIdentifier: String? = nil

    init(
        id: UUID = UUID(),
        title: String = "",
        label: String = "",
        startTime: Date = Date(),
        durationMinutes: Int? = nil,
        repeatRule: RepeatRule = .once,
        reminderMinutes: Int = 1,
        isEnabled: Bool = true,
        lastTriggeredAt: Date? = nil,
        calendarEventIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.label = label
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.repeatRule = repeatRule.rawValue
        self.reminderMinutes = reminderMinutes
        self.isEnabled = isEnabled
        self.lastTriggeredAt = lastTriggeredAt
        self.calendarEventIdentifier = calendarEventIdentifier
    }

    var rule: RepeatRule {
        RepeatRule(rawValue: repeatRule) ?? .once
    }

    /// Next fire time accounting for repeat rules. Returns `nil` if already past and `once`,
    /// or if `Calendar.date(byAdding:)` fails repeatedly (safety bound: 1000 iterations).
    var nextFireTime: Date? {
        let now = Date()
        var candidate = startTime
        // Safety bound: prevent infinite loop if Calendar.date(byAdding:) returns nil
        let maxIterations = 1000

        switch rule {
        case .once:
            return candidate > now ? candidate : nil
        case .daily:
            var i = 0
            while candidate <= now, i < maxIterations {
                candidate = Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                i += 1
            }
            return i < maxIterations ? candidate : nil
        case .weekly:
            var i = 0
            while candidate <= now, i < maxIterations {
                candidate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: candidate) ?? candidate
                i += 1
            }
            return i < maxIterations ? candidate : nil
        case .weekdays:
            var i = 0
            while (candidate <= now || !Calendar.current.isDateInWeekday(candidate)), i < maxIterations {
                candidate = Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                i += 1
            }
            return i < maxIterations ? candidate : nil
        }
    }
}

private extension Calendar {
    func isDateInWeekday(_ date: Date) -> Bool {
        let weekday = component(.weekday, from: date)
        // 1 = Sunday, 7 = Saturday
        return weekday >= 2 && weekday <= 6
    }
}
