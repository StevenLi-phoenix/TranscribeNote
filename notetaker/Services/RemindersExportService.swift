import Foundation
import EventKit
import os

/// Exports action items to Apple Reminders and Calendar via EventKit.
///
/// Requires `com.apple.security.personal-information.calendars` entitlement.
nonisolated final class RemindersExportService: @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "RemindersExportService"
    )

    private let store = EKEventStore()

    // MARK: - Reminders

    /// Request access to Reminders and export action items.
    /// Returns the number of successfully created reminders.
    func exportToReminders(actionItems: [ActionItem], sessionTitle: String) async throws -> Int {
        let granted = try await store.requestFullAccessToReminders()
        guard granted else {
            Self.logger.warning("Reminders access not granted")
            throw ExportError.accessDenied("Reminders")
        }

        let calendar = store.defaultCalendarForNewReminders()
        guard let calendar else {
            Self.logger.error("No default Reminders list found")
            throw ExportError.noDefaultList
        }

        var created = 0
        for item in actionItems {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item.content
            reminder.calendar = calendar
            reminder.isCompleted = item.isCompleted

            if let dueDate = item.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day],
                    from: dueDate
                )
            }

            var notes: [String] = []
            if !sessionTitle.isEmpty {
                notes.append("From: \(sessionTitle)")
            }
            if let assignee = item.assignee, !assignee.isEmpty {
                notes.append("Assignee: \(assignee)")
            }
            if !notes.isEmpty {
                reminder.notes = notes.joined(separator: "\n")
            }

            do {
                try store.save(reminder, commit: false)
                created += 1
            } catch {
                Self.logger.error("Failed to create reminder for '\(item.content)': \(error.localizedDescription)")
            }
        }

        try store.commit()
        Self.logger.info("Exported \(created)/\(actionItems.count) action items to Reminders")
        return created
    }

    // MARK: - Calendar

    /// Export action items with due dates as calendar events.
    /// Returns the number of successfully created events.
    func exportToCalendar(actionItems: [ActionItem], sessionTitle: String) async throws -> Int {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            Self.logger.warning("Calendar access not granted")
            throw ExportError.accessDenied("Calendar")
        }

        guard let calendar = store.defaultCalendarForNewEvents else {
            Self.logger.error("No default calendar found")
            throw ExportError.noDefaultList
        }

        var created = 0
        for item in actionItems {
            guard let dueDate = item.dueDate else { continue }

            let event = EKEvent(eventStore: store)
            event.title = item.content
            event.calendar = calendar
            event.isAllDay = true
            event.startDate = dueDate
            event.endDate = dueDate

            var notes: [String] = []
            if !sessionTitle.isEmpty {
                notes.append("From: \(sessionTitle)")
            }
            if let assignee = item.assignee, !assignee.isEmpty {
                notes.append("Assignee: \(assignee)")
            }
            notes.append("Category: \(item.itemCategory.rawValue)")
            event.notes = notes.joined(separator: "\n")

            do {
                try store.save(event, span: .thisEvent, commit: false)
                created += 1
            } catch {
                Self.logger.error("Failed to create event for '\(item.content)': \(error.localizedDescription)")
            }
        }

        try store.commit()
        Self.logger.info("Exported \(created)/\(actionItems.count) action items to Calendar")
        return created
    }

    // MARK: - Errors

    enum ExportError: LocalizedError {
        case accessDenied(String)
        case noDefaultList

        var errorDescription: String? {
            switch self {
            case .accessDenied(let service):
                "Access to \(service) was denied. Please grant permission in System Settings > Privacy & Security."
            case .noDefaultList:
                "No default list found. Please set a default in Reminders or Calendar app."
            }
        }
    }
}
