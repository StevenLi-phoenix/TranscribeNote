import Foundation
import SwiftData
import EventKit
import UserNotifications
import AppKit
import os

/// Manages the list of `ScheduledRecording` objects and bridges `SchedulerService` + `CalendarService`.
///
/// Observes `Notification.Name.scheduledRecordingDidFire` to auto-start recording via `RecordingViewModel`.
/// Polls for due recordings every 30s to handle foreground auto-start independently of notifications.
@Observable
final class SchedulerViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TranscribeNote", category: "SchedulerVM")
    static let autoStartKey = "autoStartRecordingAllowed"

    // Injected dependencies
    private let schedulerService: any SchedulerServiceProtocol
    private let calendarService: CalendarService

    // State visible to Views
    var scheduledRecordings: [ScheduledRecording] = []
    var calendarEvents: [CalendarEventItem] = []
    var isLoadingCalendar = false
    var calendarError: String? = nil
    var notificationAuthGranted: Bool? = nil  // nil = not yet requested
    /// Number of duplicate events skipped during last import
    var importSkippedCount: Int = 0

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

    // 1b: Store modelContext for persistence in handleFire
    private var modelContext: ModelContext?

    // 1e: Auto-start polling timer
    private var autoStartTimer: Timer?

    init(
        schedulerService: any SchedulerServiceProtocol = SchedulerService.shared,
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
        autoStartTimer?.invalidate()
    }

    // MARK: - Load

    /// Reload from SwiftData and re-sync pending notifications.
    func load(context: ModelContext) {
        self.modelContext = context

        let descriptor = FetchDescriptor<ScheduledRecording>(
            sortBy: [SortDescriptor(\.startTime)]
        )
        scheduledRecordings = (try? context.fetch(descriptor)) ?? []
        Self.logger.info("Loaded \(self.scheduledRecordings.count) scheduled recording(s)")

        // 1c: Cancel all existing notifications before re-scheduling to prevent duplicates
        schedulerService.cancelAll()

        // Re-schedule all enabled recordings (e.g., after app relaunch)
        for recording in scheduledRecordings where recording.isEnabled {
            schedulerService.schedule(recording)
        }

        // 1e: Start auto-start polling (only once)
        startAutoStartPolling()
    }

    // MARK: - CRUD

    /// Persist a new or updated recording and schedule its notification.
    func save(_ recording: ScheduledRecording, context: ModelContext) {
        if recording.modelContext == nil {
            context.insert(recording)
        }
        context.saveQuietly()
        schedulerService.schedule(recording)
        load(context: context)
        Self.logger.info("Saved scheduled recording '\(recording.title)'")
    }

    /// Delete a recording and cancel its notification.
    func delete(_ recording: ScheduledRecording, context: ModelContext) {
        schedulerService.cancel(recording)
        context.delete(recording)
        context.saveQuietly()
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
        context.saveQuietly()
        load(context: context)
    }

    // MARK: - Notification Authorization

    func requestNotificationPermission() async {
        let granted = await schedulerService.requestAuthorization()
        await MainActor.run { self.notificationAuthGranted = granted }
    }

    // MARK: - Calendar Integration

    func importFromCalendar(context: ModelContext, days: Int = 7) async {
        await MainActor.run {
            isLoadingCalendar = true
            calendarError = nil
            importSkippedCount = 0
        }

        // 3e: Cache calendar authorization status
        let status = calendarService.authorizationStatus
        if status == .denied || status == .restricted {
            await MainActor.run {
                calendarError = "Calendar access denied. Please enable it in System Settings > Privacy."
                isLoadingCalendar = false
            }
            return
        }

        if status != .fullAccess {
            let granted = await calendarService.requestAccess()
            guard granted else {
                await MainActor.run {
                    calendarError = "Calendar access denied. Please enable it in System Settings > Privacy."
                    isLoadingCalendar = false
                }
                return
            }
        }

        let effectiveDays = max(1, days)
        let events = await calendarService.fetchUpcomingMeetings(within: 24 * effectiveDays)
        let items = events.map { CalendarEventItem(event: $0) }

        await MainActor.run {
            calendarEvents = items
            isLoadingCalendar = false
        }
    }

    /// Convert selected calendar events to ScheduledRecordings and persist them.
    func importCalendarEvents(_ items: [CalendarEventItem], context: ModelContext) {
        var skipped = 0

        for item in items {
            // 1d/3d: Duplicate detection — check calendarEventIdentifier first, then heuristic title+time
            let eventIdentifier = item.event.eventIdentifier
            let isDuplicate: Bool
            if let eventIdentifier, !eventIdentifier.isEmpty {
                isDuplicate = scheduledRecordings.contains { $0.calendarEventIdentifier == eventIdentifier }
            } else {
                isDuplicate = scheduledRecordings.contains { existing in
                    existing.title == (item.event.title ?? "Untitled Meeting") &&
                    abs(existing.startTime.timeIntervalSince(item.startDate)) < 60
                }
            }

            if isDuplicate {
                Self.logger.warning("Skipping duplicate calendar event '\(item.event.title ?? "")'")
                skipped += 1
                continue
            }

            let recording = calendarService.importAsScheduledRecording(item.event)
            context.insert(recording)
            schedulerService.schedule(recording)
            Self.logger.info("Imported calendar event '\(item.event.title ?? "")' as scheduled recording")
        }

        importSkippedCount = skipped
        if skipped > 0 {
            Self.logger.info("Skipped \(skipped) duplicate event(s) during import")
        }

        context.saveQuietly()
        load(context: context)
    }

    // MARK: - Auto-Start Polling (1e)

    private func startAutoStartPolling() {
        guard autoStartTimer == nil else { return }
        autoStartTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkAndFireDueRecordings()
        }
        autoStartTimer?.tolerance = 5.0
        Self.logger.info("Auto-start polling started (30s interval)")
    }

    private func checkAndFireDueRecordings() {
        let now = Date()
        for recording in scheduledRecordings where recording.isEnabled {
            guard let fireTime = recording.nextFireTime else { continue }
            // Fire if due (within the last 60s window to avoid missing events between polls)
            guard fireTime <= now, fireTime > now.addingTimeInterval(-60) else { continue }
            // Skip if already triggered for this fire time
            if let lastTriggered = recording.lastTriggeredAt, fireTime <= lastTriggered {
                continue
            }
            Self.logger.info("Auto-start polling: firing '\(recording.title)'")
            handleFire(recordingID: recording.id)
            break  // one at a time
        }
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

    func handleFire(recordingID: UUID) {
        guard let recording = scheduledRecordings.first(where: { $0.id == recordingID }) else {
            Self.logger.warning("scheduledRecordingDidFire: ID \(recordingID) not found in loaded recordings")
            return
        }
        Self.logger.info("Scheduled recording '\(recording.title)' fired — starting recording")

        // 1b: Persist lastTriggeredAt
        recording.lastTriggeredAt = Date()
        modelContext?.saveQuietly()

        // Re-schedule if repeating
        if recording.rule != .once {
            schedulerService.schedule(recording)
        }

        // 1a: Use !vm.isActive (covers both recording and paused state)
        guard let vm = recordingViewModel, !vm.isActive else {
            if recordingViewModel?.isActive == true {
                Self.logger.warning("Recording already active — skipping auto-start for '\(recording.title)'")
                // 2g: Notify user that scheduled recording was skipped
                sendSkipNotification(title: recording.title)
            }
            return
        }

        // 3c: Direct callback — replaces two-hop notification pattern
        let info = ScheduledRecordingInfo(
            id: recording.id,
            title: recording.title,
            durationMinutes: recording.durationMinutes
        )
        let ctx = self.modelContext

        Task { @MainActor in
            // 2f: Auto-start permission check
            let autoStartAllowed = UserDefaults.standard.bool(forKey: Self.autoStartKey)
            if autoStartAllowed {
                await vm.startRecording(modelContext: ctx, scheduledInfo: info)
            } else {
                Self.showAutoStartPrompt(vm: vm, modelContext: ctx, info: info)
            }
        }
    }

    /// Show NSAlert with suppression button for first-time auto-start permission (2f).
    @MainActor
    private static func showAutoStartPrompt(vm: RecordingViewModel, modelContext: ModelContext?, info: ScheduledRecordingInfo) {
        let alert = NSAlert()
        alert.messageText = "Start Scheduled Recording?"
        alert.informativeText = "\"\(info.title)\" is scheduled to start now."
        alert.addButton(withTitle: "Start Recording")
        alert.addButton(withTitle: "Skip")
        alert.showsSuppressionButton = true
        // macOS 11+ auto-sets suppression text to "Do not show this message again"

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: SchedulerViewModel.autoStartKey)
            }
            Task { @MainActor in
                await vm.startRecording(modelContext: modelContext, scheduledInfo: info)
            }
        }
    }

    /// Send a local notification when a scheduled recording is skipped due to conflict.
    private func sendSkipNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled recording skipped"
        content.body = "\"\(title)\" was skipped because a recording is already in progress."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "skip-\(UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to send skip notification: \(error.localizedDescription)")
            }
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
    var endDate: Date? { event.endDate }
    var calendarName: String { event.calendar?.title ?? "" }
    var location: String? { event.location }
    var notes: String? { event.notes }
}

// Note: .scheduledRecordingAutoStart notification removed in Phase 3c — auto-start now uses direct callback.
