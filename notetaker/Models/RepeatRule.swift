import Foundation

/// Recurrence rule for scheduled recordings. Raw String for SwiftData compatibility.
enum RepeatRule: String, CaseIterable, Identifiable {
    case once = "once"
    case daily = "daily"
    case weekly = "weekly"
    case weekdays = "weekdays"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once: String(localized: "Once")
        case .daily: String(localized: "Every day")
        case .weekly: String(localized: "Every week")
        case .weekdays: String(localized: "Weekdays (Mon–Fri)")
        }
    }
}
