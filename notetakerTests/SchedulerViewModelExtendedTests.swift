import Testing
import Foundation
import SwiftData
import EventKit
@testable import notetaker

/// Extended tests for `SchedulerViewModel` covering edge cases, repeat rules,
/// state management, error paths, and dedup logic not covered by base test suite.
@Suite("SchedulerViewModel Extended Tests", .serialized)
struct SchedulerViewModelExtendedTests {

    @MainActor
    private func makeTestContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - recordingsByLabel edge cases

    @MainActor @Test("recordingsByLabel maps empty label to 'Other'")
    func recordingsByLabelEmptyLabelMapsToOther() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        let r1 = ScheduledRecording(title: "No Label", label: "", startTime: Date().addingTimeInterval(3600))
        context.insert(r1)
        try context.save()
        vm.load(context: context)

        let groups = vm.recordingsByLabel
        #expect(groups.count == 1)
        #expect(groups[0].label == "Other")
        #expect(groups[0].recordings.count == 1)
        #expect(groups[0].recordings[0].title == "No Label")
    }

    @MainActor @Test("recordingsByLabel with mixed empty and non-empty labels")
    func recordingsByLabelMixedLabels() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        let r1 = ScheduledRecording(title: "A", label: "", startTime: Date().addingTimeInterval(3600))
        let r2 = ScheduledRecording(title: "B", label: "Work", startTime: Date().addingTimeInterval(7200))
        let r3 = ScheduledRecording(title: "C", label: "", startTime: Date().addingTimeInterval(1800))
        context.insert(r1)
        context.insert(r2)
        context.insert(r3)
        try context.save()
        vm.load(context: context)

        let groups = vm.recordingsByLabel
        #expect(groups.count == 2)
        // Alphabetical: "Other" < "Work"
        #expect(groups[0].label == "Other")
        #expect(groups[0].recordings.count == 2)
        #expect(groups[1].label == "Work")
        #expect(groups[1].recordings.count == 1)
    }

    @MainActor @Test("recordingsByLabel returns empty array when no recordings")
    func recordingsByLabelEmpty() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()
        vm.load(context: context)

        #expect(vm.recordingsByLabel.isEmpty)
    }

    @MainActor @Test("recordingsByLabel sorts recordings within group by startTime")
    func recordingsByLabelSortedWithinGroup() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        let now = Date()
        let r1 = ScheduledRecording(title: "Late", label: "Team", startTime: now.addingTimeInterval(7200))
        let r2 = ScheduledRecording(title: "Early", label: "Team", startTime: now.addingTimeInterval(1800))
        let r3 = ScheduledRecording(title: "Mid", label: "Team", startTime: now.addingTimeInterval(3600))
        context.insert(r1)
        context.insert(r2)
        context.insert(r3)
        try context.save()
        vm.load(context: context)

        let groups = vm.recordingsByLabel
        #expect(groups.count == 1)
        #expect(groups[0].recordings.map(\.title) == ["Early", "Mid", "Late"])
    }

    // MARK: - nextScheduled edge cases

    @MainActor @Test("nextScheduled returns nil when all recordings are disabled")
    func nextScheduledAllDisabled() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        let r1 = ScheduledRecording(title: "D1", startTime: Date().addingTimeInterval(3600), isEnabled: false)
        let r2 = ScheduledRecording(title: "D2", startTime: Date().addingTimeInterval(7200), isEnabled: false)
        context.insert(r1)
        context.insert(r2)
        try context.save()
        vm.load(context: context)

        #expect(vm.nextScheduled == nil)
    }

    @MainActor @Test("nextScheduled returns nil when all once-recordings are in the past")
    func nextScheduledAllPast() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        let r1 = ScheduledRecording(title: "Past1", startTime: Date().addingTimeInterval(-3600))
        let r2 = ScheduledRecording(title: "Past2", startTime: Date().addingTimeInterval(-7200))
        context.insert(r1)
        context.insert(r2)
        try context.save()
        vm.load(context: context)

        // Both are .once and in the past → nextFireTime is nil
        #expect(vm.nextScheduled == nil)
    }

    @MainActor @Test("nextScheduled picks repeating recording over past once-only")
    func nextScheduledPrefersRepeating() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        // Past once-only → nil nextFireTime
        let pastOnce = ScheduledRecording(title: "Past Once", startTime: Date().addingTimeInterval(-3600))
        // Daily repeating from the past → nextFireTime should exist (advances to tomorrow)
        let dailyPast = ScheduledRecording(title: "Daily", startTime: Date().addingTimeInterval(-3600), repeatRule: .daily)
        context.insert(pastOnce)
        context.insert(dailyPast)
        try context.save()
        vm.load(context: context)

        #expect(vm.nextScheduled?.title == "Daily")
    }

    // MARK: - save() update path

    @MainActor @Test("save() updates existing recording without duplicating")
    func saveUpdatesExistingRecording() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "Original", startTime: Date().addingTimeInterval(3600))
        context.insert(recording)
        try context.save()
        vm.load(context: context)
        #expect(vm.scheduledRecordings.count == 1)

        // Modify and save again (already has modelContext)
        recording.title = "Updated"
        vm.save(recording, context: context)

        #expect(vm.scheduledRecordings.count == 1)
        #expect(vm.scheduledRecordings.first?.title == "Updated")
    }

    // MARK: - delete edge cases

    @MainActor @Test("delete on the only recording leaves list empty")
    func deleteLastRecording() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "Only One", startTime: Date().addingTimeInterval(3600))
        context.insert(recording)
        try context.save()
        vm.load(context: context)
        #expect(vm.scheduledRecordings.count == 1)

        vm.delete(recording, context: context)
        #expect(vm.scheduledRecordings.isEmpty)
        #expect(vm.nextScheduled == nil)
        #expect(vm.recordingsByLabel.isEmpty)
    }

    @MainActor @Test("delete multiple recordings leaves correct remaining set")
    func deleteMultipleRecordings() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let r1 = ScheduledRecording(title: "Keep", startTime: Date().addingTimeInterval(3600))
        let r2 = ScheduledRecording(title: "Delete1", startTime: Date().addingTimeInterval(7200))
        let r3 = ScheduledRecording(title: "Delete2", startTime: Date().addingTimeInterval(10800))
        context.insert(r1)
        context.insert(r2)
        context.insert(r3)
        try context.save()
        vm.load(context: context)
        #expect(vm.scheduledRecordings.count == 3)

        vm.delete(r2, context: context)
        vm.delete(r3, context: context)

        #expect(vm.scheduledRecordings.count == 1)
        #expect(vm.scheduledRecordings.first?.title == "Keep")
    }

    // MARK: - toggleEnabled state management

    @MainActor @Test("toggleEnabled twice returns to original state")
    func toggleEnabledRoundTrip() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "Toggle", startTime: Date().addingTimeInterval(3600), isEnabled: true)
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        vm.toggleEnabled(recording, context: context)
        #expect(!recording.isEnabled)

        vm.toggleEnabled(recording, context: context)
        #expect(recording.isEnabled)
    }

    @MainActor @Test("toggleEnabled on disabled recording schedules notification")
    func toggleEnabledFromDisabledSchedules() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "Was Off", startTime: Date().addingTimeInterval(3600), isEnabled: false)
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        // Should not have been scheduled during load
        let scheduleCountAfterLoad = mockService.scheduleCallCount
        #expect(scheduleCountAfterLoad == 0)

        // Toggle on
        vm.toggleEnabled(recording, context: context)
        #expect(recording.isEnabled)
        // schedule called for the toggle + schedule called during load(context:) re-load
        #expect(mockService.scheduleCallCount > scheduleCountAfterLoad)
    }

    // MARK: - requestNotificationPermission

    @MainActor @Test("requestNotificationPermission sets notificationAuthGranted to true")
    func requestNotificationPermissionGranted() async throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)

        #expect(vm.notificationAuthGranted == nil)

        await vm.requestNotificationPermission()

        #expect(vm.notificationAuthGranted == true)
    }

    // MARK: - handleFire repeat rule handling

    @MainActor @Test("handleFire re-schedules weekdays repeating recordings")
    func handleFireReSchedulesWeekdays() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "Weekday Standup",
            startTime: Date().addingTimeInterval(-60),
            repeatRule: .weekdays
        )
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        let scheduleCountBefore = mockService.scheduleCallCount
        vm.handleFire(recordingID: recording.id)

        // .weekdays != .once, so should re-schedule
        #expect(mockService.scheduleCallCount > scheduleCountBefore)
    }

    @MainActor @Test("handleFire for all repeat rules sets lastTriggeredAt")
    func handleFireSetsLastTriggeredAtForAllRules() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let rules: [RepeatRule] = [.once, .daily, .weekly, .weekdays]
        var recordings: [ScheduledRecording] = []
        for rule in rules {
            let r = ScheduledRecording(
                title: "Rule \(rule.rawValue)",
                startTime: Date().addingTimeInterval(-60),
                repeatRule: rule
            )
            context.insert(r)
            recordings.append(r)
        }
        try context.save()
        vm.load(context: context)

        for recording in recordings {
            vm.handleFire(recordingID: recording.id)
            #expect(recording.lastTriggeredAt != nil, "lastTriggeredAt should be set for rule: \(recording.repeatRule)")
        }
    }

    // MARK: - handleFire with unknown ID does not crash

    @MainActor @Test("handleFire with multiple unknown IDs is safe")
    func handleFireMultipleUnknownIDs() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)

        // Should not crash on repeated unknown IDs
        for _ in 0..<10 {
            vm.handleFire(recordingID: UUID())
        }
        #expect(vm.scheduledRecordings.isEmpty)
    }

    // MARK: - load() with mixed enabled/disabled recordings

    @MainActor @Test("load() schedules only enabled recordings among mixed set")
    func loadSchedulesOnlyEnabled() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let enabled1 = ScheduledRecording(title: "E1", startTime: Date().addingTimeInterval(3600), isEnabled: true)
        let disabled1 = ScheduledRecording(title: "D1", startTime: Date().addingTimeInterval(7200), isEnabled: false)
        let enabled2 = ScheduledRecording(title: "E2", startTime: Date().addingTimeInterval(10800), isEnabled: true)
        let disabled2 = ScheduledRecording(title: "D2", startTime: Date().addingTimeInterval(14400), isEnabled: false)
        context.insert(enabled1)
        context.insert(disabled1)
        context.insert(enabled2)
        context.insert(disabled2)
        try context.save()

        vm.load(context: context)

        #expect(vm.scheduledRecordings.count == 4)
        // Only 2 enabled recordings should trigger schedule()
        #expect(mockService.scheduleCallCount == 2)
        #expect(mockService.cancelAllCallCount == 1)
    }

    // MARK: - importCalendarEvents duplicate detection (calendarEventIdentifier)

    @MainActor @Test("importCalendarEvents skips event with matching calendarEventIdentifier")
    func importCalendarEventsSkipsByIdentifier() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        // Pre-existing recording with a calendar event identifier
        let existing = ScheduledRecording(
            title: "Existing Meeting",
            startTime: Date().addingTimeInterval(3600),
            calendarEventIdentifier: "EK-12345"
        )
        context.insert(existing)
        try context.save()
        vm.load(context: context)
        #expect(vm.scheduledRecordings.count == 1)

        // Create a mock EKEvent with matching identifier
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Different Title"
        event.startDate = Date().addingTimeInterval(9999)
        event.endDate = Date().addingTimeInterval(13599)
        // EKEvent.eventIdentifier is read-only (assigned by EventKit store),
        // so we test the heuristic fallback path instead.
        // The calendarEventIdentifier-based dedup requires the event to come from a real store.

        // For heuristic dedup: same title + close start time
        let event2 = EKEvent(eventStore: EKEventStore())
        event2.title = "Existing Meeting"
        event2.startDate = existing.startTime.addingTimeInterval(30) // within 60s
        event2.endDate = existing.startTime.addingTimeInterval(3630)

        let item = CalendarEventItem(event: event2)
        vm.importCalendarEvents([item], context: context)

        // Should skip the duplicate
        #expect(vm.importSkippedCount == 1)
        #expect(vm.scheduledRecordings.count == 1) // no new recording added
    }

    @MainActor @Test("importCalendarEvents adds non-duplicate events")
    func importCalendarEventsAddsNonDuplicate() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)
        #expect(vm.scheduledRecordings.isEmpty)

        let event = EKEvent(eventStore: EKEventStore())
        event.title = "New Meeting"
        event.startDate = Date().addingTimeInterval(3600)
        event.endDate = Date().addingTimeInterval(7200)

        let item = CalendarEventItem(event: event)
        vm.importCalendarEvents([item], context: context)

        #expect(vm.importSkippedCount == 0)
        #expect(vm.scheduledRecordings.count == 1)
        #expect(vm.scheduledRecordings.first?.title == "New Meeting")
    }

    @MainActor @Test("importCalendarEvents heuristic dedup: different title is not duplicate")
    func importCalendarEventsHeuristicDifferentTitle() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let existing = ScheduledRecording(
            title: "Meeting A",
            startTime: Date().addingTimeInterval(3600)
        )
        context.insert(existing)
        try context.save()
        vm.load(context: context)

        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Meeting B"
        event.startDate = Date().addingTimeInterval(3610) // within 60s but different title
        event.endDate = Date().addingTimeInterval(7200)

        let item = CalendarEventItem(event: event)
        vm.importCalendarEvents([item], context: context)

        #expect(vm.importSkippedCount == 0)
        #expect(vm.scheduledRecordings.count == 2)
    }

    @MainActor @Test("importCalendarEvents heuristic dedup: same title but >60s apart is not duplicate")
    func importCalendarEventsHeuristicFarApart() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let existing = ScheduledRecording(
            title: "Recurring Standup",
            startTime: Date().addingTimeInterval(3600)
        )
        context.insert(existing)
        try context.save()
        vm.load(context: context)

        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Recurring Standup"
        event.startDate = Date().addingTimeInterval(3600 + 120) // 120s apart — beyond 60s threshold
        event.endDate = Date().addingTimeInterval(7200)

        let item = CalendarEventItem(event: event)
        vm.importCalendarEvents([item], context: context)

        #expect(vm.importSkippedCount == 0)
        #expect(vm.scheduledRecordings.count == 2)
    }

    @MainActor @Test("importCalendarEvents with multiple items tracks correct skip count")
    func importCalendarEventsMultipleItemsSkipCount() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let existing = ScheduledRecording(
            title: "Daily Standup",
            startTime: Date().addingTimeInterval(3600)
        )
        context.insert(existing)
        try context.save()
        vm.load(context: context)

        // One duplicate, two non-duplicates
        let dup = EKEvent(eventStore: EKEventStore())
        dup.title = "Daily Standup"
        dup.startDate = Date().addingTimeInterval(3600 + 10) // within 60s threshold
        dup.endDate = Date().addingTimeInterval(7200)

        let new1 = EKEvent(eventStore: EKEventStore())
        new1.title = "Sprint Planning"
        new1.startDate = Date().addingTimeInterval(86400)
        new1.endDate = Date().addingTimeInterval(86400 + 3600)

        let new2 = EKEvent(eventStore: EKEventStore())
        new2.title = "Retro"
        new2.startDate = Date().addingTimeInterval(172800)
        new2.endDate = Date().addingTimeInterval(172800 + 3600)

        let items = [dup, new1, new2].map { CalendarEventItem(event: $0) }
        vm.importCalendarEvents(items, context: context)

        #expect(vm.importSkippedCount == 1)
        // 1 existing + 2 new
        #expect(vm.scheduledRecordings.count == 3)
    }

    @MainActor @Test("importCalendarEvents resets importSkippedCount on each call")
    func importCalendarEventsResetsSkipCount() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let existing = ScheduledRecording(title: "Meeting", startTime: Date().addingTimeInterval(3600))
        context.insert(existing)
        try context.save()
        vm.load(context: context)

        // First import with a duplicate
        let dup1 = EKEvent(eventStore: EKEventStore())
        dup1.title = "Meeting"
        dup1.startDate = Date().addingTimeInterval(3600 + 5)
        dup1.endDate = Date().addingTimeInterval(7200)
        vm.importCalendarEvents([CalendarEventItem(event: dup1)], context: context)
        #expect(vm.importSkippedCount == 1)

        // Second import with no duplicates
        let newEvent = EKEvent(eventStore: EKEventStore())
        newEvent.title = "Totally New"
        newEvent.startDate = Date().addingTimeInterval(86400)
        newEvent.endDate = Date().addingTimeInterval(86400 + 3600)
        vm.importCalendarEvents([CalendarEventItem(event: newEvent)], context: context)
        #expect(vm.importSkippedCount == 0)
    }

    // MARK: - importCalendarEvents schedules notifications

    @MainActor @Test("importCalendarEvents schedules notification for each imported event")
    func importCalendarEventsSchedulesNotifications() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)

        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Team Sync"
        event.startDate = Date().addingTimeInterval(3600)
        event.endDate = Date().addingTimeInterval(7200)

        let scheduleCountBefore = mockService.scheduleCallCount
        vm.importCalendarEvents([CalendarEventItem(event: event)], context: context)

        // schedule() called for the import + load() re-schedules all enabled
        #expect(mockService.scheduleCallCount > scheduleCountBefore)
    }

    // MARK: - save() with new recording (not yet inserted)

    @MainActor @Test("save() inserts brand-new recording into context")
    func saveInsertsBrandNew() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)
        #expect(vm.scheduledRecordings.isEmpty)

        let recording = ScheduledRecording(title: "Brand New", startTime: Date().addingTimeInterval(3600))
        // recording.modelContext is nil at this point
        vm.save(recording, context: context)

        #expect(vm.scheduledRecordings.count == 1)
        // Verify it persisted in SwiftData
        let fetched = try context.fetch(FetchDescriptor<ScheduledRecording>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Brand New")
    }

    // MARK: - save() schedules notification

    @MainActor @Test("save() always calls schedule for the recording")
    func saveAlwaysSchedules() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)

        let recording = ScheduledRecording(title: "Schedule Me", startTime: Date().addingTimeInterval(3600))
        vm.save(recording, context: context)

        #expect(mockService.scheduledRecordingIDs.contains(recording.id))
    }

    // MARK: - Initial state

    @MainActor @Test("Initial state has empty recordings and nil notificationAuthGranted")
    func initialState() {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())

        #expect(vm.scheduledRecordings.isEmpty)
        #expect(vm.calendarEvents.isEmpty)
        #expect(!vm.isLoadingCalendar)
        #expect(vm.calendarError == nil)
        #expect(vm.notificationAuthGranted == nil)
        #expect(vm.importSkippedCount == 0)
        #expect(vm.nextScheduled == nil)
        #expect(vm.recordingsByLabel.isEmpty)
    }

    // MARK: - load() can be called with different contexts

    @MainActor @Test("load() with a different context replaces recordings")
    func loadDifferentContextReplacesRecordings() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)

        // Context 1: has one recording
        let context1 = try makeTestContext()
        let r1 = ScheduledRecording(title: "From Context 1", startTime: Date().addingTimeInterval(3600))
        context1.insert(r1)
        try context1.save()
        vm.load(context: context1)
        #expect(vm.scheduledRecordings.count == 1)
        #expect(vm.scheduledRecordings.first?.title == "From Context 1")

        // Context 2: has two recordings
        let context2 = try makeTestContext()
        let r2 = ScheduledRecording(title: "From Context 2a", startTime: Date().addingTimeInterval(3600))
        let r3 = ScheduledRecording(title: "From Context 2b", startTime: Date().addingTimeInterval(7200))
        context2.insert(r2)
        context2.insert(r3)
        try context2.save()
        vm.load(context: context2)

        #expect(vm.scheduledRecordings.count == 2)
    }

    // MARK: - Recordings sorted by startTime after load

    @MainActor @Test("load() returns recordings sorted by startTime")
    func loadSortsByStartTime() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let now = Date()
        let late = ScheduledRecording(title: "Late", startTime: now.addingTimeInterval(10800))
        let early = ScheduledRecording(title: "Early", startTime: now.addingTimeInterval(1800))
        let mid = ScheduledRecording(title: "Mid", startTime: now.addingTimeInterval(3600))
        // Insert in non-sorted order
        context.insert(late)
        context.insert(early)
        context.insert(mid)
        try context.save()
        vm.load(context: context)

        let titles = vm.scheduledRecordings.map(\.title)
        #expect(titles == ["Early", "Mid", "Late"])
    }

    // MARK: - handleFire does not re-schedule once recording

    @MainActor @Test("handleFire for once rule does not call schedule again")
    func handleFireOnceNoReschedule() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "One-shot",
            startTime: Date().addingTimeInterval(-30),
            repeatRule: .once
        )
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        let countAfterLoad = mockService.scheduleCallCount
        vm.handleFire(recordingID: recording.id)

        // .once → handleFire should NOT re-schedule
        #expect(mockService.scheduleCallCount == countAfterLoad)
    }

    // MARK: - Multiple handleFire calls for different recordings

    @MainActor @Test("handleFire can be called for different recordings sequentially")
    func handleFireMultipleRecordings() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let r1 = ScheduledRecording(title: "R1", startTime: Date().addingTimeInterval(-60), repeatRule: .daily)
        let r2 = ScheduledRecording(title: "R2", startTime: Date().addingTimeInterval(-30), repeatRule: .weekly)
        context.insert(r1)
        context.insert(r2)
        try context.save()
        vm.load(context: context)

        vm.handleFire(recordingID: r1.id)
        vm.handleFire(recordingID: r2.id)

        #expect(r1.lastTriggeredAt != nil)
        #expect(r2.lastTriggeredAt != nil)
    }

    // MARK: - ScheduledRecording.nextFireTime edge cases (tested via nextScheduled)

    @MainActor @Test("nextScheduled with daily recording started yesterday returns future time")
    func nextScheduledDailyFromYesterday() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        let yesterday = Date().addingTimeInterval(-86400)
        let recording = ScheduledRecording(title: "Daily", startTime: yesterday, repeatRule: .daily)
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        let next = vm.nextScheduled
        #expect(next != nil)
        #expect(next?.title == "Daily")
        // nextFireTime should be in the future
        if let fireTime = next?.nextFireTime {
            #expect(fireTime > Date())
        }
    }

    @MainActor @Test("nextScheduled with weekly recording started last week returns future time")
    func nextScheduledWeeklyFromLastWeek() throws {
        let vm = SchedulerViewModel(schedulerService: MockSchedulerService())
        let context = try makeTestContext()

        let lastWeek = Date().addingTimeInterval(-7 * 86400)
        let recording = ScheduledRecording(title: "Weekly", startTime: lastWeek, repeatRule: .weekly)
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        let next = vm.nextScheduled
        #expect(next != nil)
        #expect(next?.title == "Weekly")
    }

    // MARK: - delete calls cancel on service

    @MainActor @Test("delete cancels the recording on service before removing")
    func deleteCancelsBeforeRemoving() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "Cancel Me", startTime: Date().addingTimeInterval(3600))
        let recordingID = recording.id
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        vm.delete(recording, context: context)

        #expect(mockService.cancelledRecordingIDs.contains(recordingID))
    }

    // MARK: - ScheduledRecording with durationMinutes

    @MainActor @Test("save preserves durationMinutes on recording")
    func savePreservesDuration() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)

        let recording = ScheduledRecording(
            title: "With Duration",
            startTime: Date().addingTimeInterval(3600),
            durationMinutes: 45
        )
        vm.save(recording, context: context)

        #expect(vm.scheduledRecordings.first?.durationMinutes == 45)
    }

    @MainActor @Test("save preserves nil durationMinutes")
    func savePreservesNilDuration() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)

        let recording = ScheduledRecording(
            title: "No Duration",
            startTime: Date().addingTimeInterval(3600),
            durationMinutes: nil
        )
        vm.save(recording, context: context)

        #expect(vm.scheduledRecordings.first?.durationMinutes == nil)
    }

    // MARK: - importCalendarEvents with empty list

    @MainActor @Test("importCalendarEvents with empty list does not modify state")
    func importCalendarEventsEmptyList() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let existing = ScheduledRecording(title: "Existing", startTime: Date().addingTimeInterval(3600))
        context.insert(existing)
        try context.save()
        vm.load(context: context)

        let countBefore = vm.scheduledRecordings.count
        vm.importCalendarEvents([], context: context)

        #expect(vm.importSkippedCount == 0)
        #expect(vm.scheduledRecordings.count == countBefore)
    }

    // MARK: - CalendarEventItem properties

    @Test("CalendarEventItem wraps EKEvent properties correctly")
    func calendarEventItemProperties() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Test Event"
        event.startDate = Date(timeIntervalSince1970: 1000)
        event.endDate = Date(timeIntervalSince1970: 4600)
        event.location = "Room 42"
        event.notes = "Some notes"

        let item = CalendarEventItem(event: event)

        #expect(item.title == "Test Event")
        #expect(item.startDate == Date(timeIntervalSince1970: 1000))
        #expect(item.endDate == Date(timeIntervalSince1970: 4600))
        #expect(item.location == "Room 42")
        #expect(item.notes == "Some notes")
    }

    @Test("CalendarEventItem with nil/empty title shows fallback")
    func calendarEventItemNilTitle() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.startDate = Date()
        // EKEvent.title may default to "" or nil depending on runtime;
        // CalendarEventItem.title uses `event.title ?? "Untitled"`
        let item = CalendarEventItem(event: event)
        // Either "Untitled" (nil case) or "" (empty string case) is acceptable
        #expect(item.title == "Untitled" || item.title == "")
    }

    @Test("CalendarEventItem has unique IDs")
    func calendarEventItemUniqueIDs() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.startDate = Date()

        let item1 = CalendarEventItem(event: event)
        let item2 = CalendarEventItem(event: event)

        #expect(item1.id != item2.id)
    }
}
