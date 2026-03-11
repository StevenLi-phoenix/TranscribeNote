import Foundation
import SwiftData
import EventKit
import os

/// Manages the list of `ScheduledRecording` objects and bridges `SchedulerService` + `CalendarService`.
///
/// Observes `Notification.Name.scheduledRecordingDidFire` to auto-start recording via `RecordingViewModel`.
@Observable
final class SchedulerViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SchedulerVM")

    // Injected dependencies
    private let schedulerService: SchedulerService
    private let calendarService: CalendarService

    // State visible to Views
    var scheduledRecordings: [ScheduledRecording] = []
    var calendarEvents: [CalendarEventItem] = []
    var isLoadingCalendar = false
    var calendarError: String? = nil
    var notificationAuthGranted: Bool? = nil  // nil = not yet requested

    // Grouped by label for display
    var recordingsByLabel: [(label: String, recordings: [ScheduledRecording])] {
        let grouped = Dictionary(grouping: scheduledRecordings) { $0.label.isEmpty ? "Other" : $0.label }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (label: $0.key, recordings: $0.value.sorted { $0.startTime < $1.startTime }) }
    }

    var nextScheduled: ScheduledRecording? {
        scheduledRecordings
            .filter { $0.isEnabled && $0.nextFireTime != nil }
            .sorted { ($0.nextFireTime ?? .distantFuture) < ($1.nextFireTime ?? .distantFuture) }
            .first
    }

    private var fireObserver: NSObjectProtocol?
    weak var recordingViewModel: RecordingViewModel?

    init(
        schedulerService: SchedulerService = .shared,
        calendarService: CalendarService = CalendarService()
    ) {
        self.schedulerService = schedulerService
        self.calendarService = calendarService
        listenForFires()
    }

    deinit {
        if let observer = fireObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Load

    /// Reload from SwiftData and re-sync pending notifications.
    func load(context: ModelContext) {
        let descriptor = FetchDescriptor<ScheduledRecording>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        scheduledRecordings = (try? context.fetch(descriptor)) ?? []
        Self.logger.info("Loaded \(self.scheduledRecordings.count) scheduled recording(s)")

        // Re-schedule all enabled recordings (e.g., after app relaunch)
        for recording in scheduledRecordings where recording.isEnabled {
            schedulerService.schedule(recording)
        }
    }

    // MARK: - CRUD

    /// Persist a new or updated recording and schedule its notification.
    func save(_ recording: ScheduledRecording, context: ModelContext) {
        if recording.modelContext == nil {
            context.insert(recording)
        }
        try? context.save()
        schedulerService.schedule(recording)
        load(context: context)
        Self.logger.info("Saved scheduled recording '\(recording.title)'")
    }

    /// Delete a recording and cancel its notification.
    func delete(_ recording: ScheduledRecording, context: ModelContext) {
        schedulerService.cancel(recording)
        context.delete(recording)
        try? context.save()
        load(context: context)
        Self.logger.info("Deleted scheduled recording '\(recording.title)'")
    }

    func toggleEnabled(_ recording: ScheduledRecording, context: ModelContext) {
        recording.isEnabled.toggle()
        if recording.isEnabled {
            schedulerService.schedule(recording)
        } else {
            schedulerService.cancel(recording)
        }
        try? context.save()
        load(context: context)
    }

    // MARK: - Notification Authorization

    func requestNotificationPermission() async {
        let granted = await schedulerService.requestAuthorization()
        await MainActor.run { self.notificationAuthGranted = granted }
    }

    // MARK: - Calendar Integration

    func importFromCalendar(context: ModelContext) async {
        await MainActor.run {
            isLoadingCalendar = true
            calendarError = nil
        }

        let granted = await calendarService.requestAccess()
        guard granted else {
            await MainActor.run {
                calendarError = "Calendar access denied. Please enable it in System Settings > Privacy."
                isLoadingCalendar = false
            }
            return
        }

        let events = await calendarService.fetchUpcomingMeetings(within: 24 * 7) // next 7 days
        let items = events.map { CalendarEventItem(event: $0) }

        await MainActor.run {
            calendarEvents = items
            isLoadingCalendar = false
        }
    }

    /// Convert selected calendar events to ScheduledRecordings and persist them.
    func importCalendarEvents(_ items: [CalendarEventItem], context: ModelContext) {
        for item in items {
            let recording = calendarService.importAsScheduledRecording(item.event)
            context.insert(recording)
            schedulerService.schedule(recording)
            Self.logger.info("Imported calendar event '\(item.event.title ?? "")' as scheduled recording")
        }
        try? context.save()
        load(context: context)
    }

    // MARK: - Fire Handling

    private func listenForFires() {
        fireObserver = NotificationCenter.default.addObserver(
            forName: .scheduledRecordingDidFire,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let recordingID = notification.object as? UUID else { return }
            self.handleFire(recordingID: recordingID)
        }
    }

    private func handleFire(recordingID: UUID) {
        guard let recording = scheduledRecordings.first(where: { $0.id == recordingID }) else {
            Self.logger.warning("scheduledRecordingDidFire: ID \(recordingID) not found in loaded recordings")
            return
        }
        Self.logger.info("Scheduled recording '\(recording.title)' fired — starting recording")

        recording.lastTriggeredAt = Date()

        // Re-schedule if repeating
        if recording.rule != .once {
            schedulerService.schedule(recording)
        }

        // Start recording via RecordingViewModel (if available and not already recording)
        guard let vm = recordingViewModel, !vm.isRecording else { return }
        Task { @MainActor in
            // modelContext is not available here; caller must provide it via delegate pattern.
            // For now, post a second notification that notetakerApp can observe with context.
            NotificationCenter.default.post(
                name: .scheduledRecordingAutoStart,
                object: recordingID
            )
        }
    }
}

// MARK: - Supporting Types

/// Wrapper around `EKEvent` for SwiftUI list display.
struct CalendarEventItem: Identifiable {
    let id = UUID()
    let event: EKEvent  // EKEvent is a class; safe to hold a reference

    var title: String { event.title ?? "Untitled" }
    var startDate: Date { event.startDate }
    var calendarName: String { event.calendar?.title ?? "" }
}

extension Notification.Name {
    static let scheduledRecordingAutoStart = Notification.Name("notetaker.scheduledRecordingAutoStart")
}
