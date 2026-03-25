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
        case .once: "Once"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .weekdays: "Weekdays (Mon–Fri)"
        }
    }
}
