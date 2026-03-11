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

    init(
        id: UUID = UUID(),
        title: String = "",
        label: String = "",
        startTime: Date = Date(),
        durationMinutes: Int? = nil,
        repeatRule: RepeatRule = .once,
        reminderMinutes: Int = 1,
        isEnabled: Bool = true,
        lastTriggeredAt: Date? = nil
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
    }

    var rule: RepeatRule {
        RepeatRule(rawValue: repeatRule) ?? .once
    }

    /// Next fire time accounting for repeat rules. Returns `nil` if already past and `once`.
    var nextFireTime: Date? {
        let now = Date()
        var candidate = startTime

        switch rule {
        case .once:
            return candidate > now ? candidate : nil
        case .daily:
            while candidate <= now {
                candidate = Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        case .weekdays:
            while candidate <= now || !Calendar.current.isDateInWeekday(candidate) {
                candidate = Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
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
