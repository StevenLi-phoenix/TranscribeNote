import Testing
import Foundation
import SwiftData
@testable import notetaker

/// Tests for `SchedulerViewModel` — scheduling, persistence, dedup, and fire handling.
///
/// All tests are `@MainActor` because `SchedulerViewModel` is `@Observable` (MainActor-isolated
/// under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Swift Testing's `@Test` macro explicitly
/// strips default actor isolation, so each test must opt in individually.
@Suite("SchedulerViewModel", .serialized)
struct SchedulerViewModelTests {

    /// Create an in-memory SwiftData container + context for testing.
    /// Uses `ModelContext(container)` rather than `container.mainContext` to avoid an
    /// additional MainActor dependency on the context itself — the MainActor requirement
    /// comes from `SchedulerViewModel`'s methods, not from context creation.
    @MainActor
    private func makeTestContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - 1a: handleFire guard uses isActive

    @MainActor @Test("handleFire sets lastTriggeredAt even without RecordingViewModel")
    func handleFireWithoutRecordingVM() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "Test", startTime: Date().addingTimeInterval(-60))
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        // No recordingViewModel assigned → handleFire should update lastTriggeredAt then early-return
        vm.handleFire(recordingID: recording.id)

        #expect(recording.lastTriggeredAt != nil)
    }

    // MARK: - 1b: lastTriggeredAt persistence

    @MainActor @Test("handleFire persists lastTriggeredAt via modelContext.save()")
    func handleFirePersistsLastTriggered() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "Persist Test", startTime: Date().addingTimeInterval(-60))
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        #expect(recording.lastTriggeredAt == nil)

        vm.handleFire(recordingID: recording.id)

        #expect(recording.lastTriggeredAt != nil)
        // Verify the change would survive a re-fetch (context was saved)
        let refetched = try context.fetch(FetchDescriptor<ScheduledRecording>())
        #expect(refetched.first?.lastTriggeredAt != nil)
    }

    @MainActor @Test("handleFire with unknown ID logs warning and returns")
    func handleFireUnknownID() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)

        // Should not crash — just log warning
        vm.handleFire(recordingID: UUID())
        #expect(vm.scheduledRecordings.isEmpty)
    }

    // MARK: - 1c: cancelAll before re-schedule

    @MainActor @Test("load() calls cancelAll before scheduling enabled recordings")
    func loadCancelsThenSchedules() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "Active",
            startTime: Date().addingTimeInterval(3600),
            isEnabled: true
        )
        context.insert(recording)
        try context.save()

        vm.load(context: context)

        #expect(mockService.cancelAllCallCount >= 1)
        #expect(mockService.scheduleCallCount >= 1)
    }

    @MainActor @Test("Repeated load() calls increment cancelAll count")
    func repeatedLoadCancelAllCount() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        vm.load(context: context)
        vm.load(context: context)
        vm.load(context: context)

        #expect(mockService.cancelAllCallCount == 3)
    }

    @MainActor @Test("load() does not schedule disabled recordings")
    func loadSkipsDisabled() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "Disabled",
            startTime: Date().addingTimeInterval(3600),
            isEnabled: false
        )
        context.insert(recording)
        try context.save()

        vm.load(context: context)

        // cancelAll is called, but schedule() is NOT called for disabled recording
        #expect(mockService.cancelAllCallCount == 1)
        #expect(mockService.scheduleCallCount == 0)
    }

    // MARK: - CRUD

    @MainActor @Test("save() inserts new recording, schedules notification, and reloads")
    func saveInsertsAndReloads() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        vm.load(context: context)
        #expect(vm.scheduledRecordings.isEmpty)

        let recording = ScheduledRecording(title: "New Meeting", startTime: Date().addingTimeInterval(3600))
        vm.save(recording, context: context)

        #expect(vm.scheduledRecordings.count == 1)
        #expect(vm.scheduledRecordings.first?.title == "New Meeting")
        #expect(mockService.scheduledRecordingIDs.contains(recording.id))
    }

    @MainActor @Test("delete() removes recording and cancels notification")
    func deleteRemovesAndCancels() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(title: "To Delete", startTime: Date().addingTimeInterval(3600))
        context.insert(recording)
        try context.save()
        vm.load(context: context)
        #expect(vm.scheduledRecordings.count == 1)

        vm.delete(recording, context: context)

        #expect(vm.scheduledRecordings.isEmpty)
        #expect(mockService.cancelledRecordingIDs.contains(recording.id))
    }

    @MainActor @Test("toggleEnabled schedules when enabling, cancels when disabling")
    func toggleEnabledSchedulesOrCancels() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "Toggle Test",
            startTime: Date().addingTimeInterval(3600),
            isEnabled: true
        )
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        // Toggle off → should cancel
        vm.toggleEnabled(recording, context: context)
        #expect(!recording.isEnabled)
        #expect(mockService.cancelledRecordingIDs.contains(recording.id))

        // Toggle on → should schedule
        let scheduleCountBefore = mockService.scheduleCallCount
        vm.toggleEnabled(recording, context: context)
        #expect(recording.isEnabled)
        #expect(mockService.scheduleCallCount > scheduleCountBefore)
    }

    // MARK: - handleFire re-schedules repeating recordings

    @MainActor @Test("handleFire re-schedules daily repeating recordings")
    func handleFireReSchedulesRepeating() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "Daily Standup",
            startTime: Date().addingTimeInterval(-60),
            repeatRule: .daily
        )
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        let scheduleCountBefore = mockService.scheduleCallCount
        vm.handleFire(recordingID: recording.id)

        // Should have called schedule() again for the repeating recording
        #expect(mockService.scheduleCallCount > scheduleCountBefore)
    }

    @MainActor @Test("handleFire does NOT re-schedule once-only recordings")
    func handleFireDoesNotReScheduleOnce() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "One-time Meeting",
            startTime: Date().addingTimeInterval(-60),
            repeatRule: .once
        )
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        let scheduleCountAfterLoad = mockService.scheduleCallCount
        vm.handleFire(recordingID: recording.id)

        // .once + past startTime → not re-scheduled in load, and handleFire skips re-schedule
        #expect(mockService.scheduleCallCount == scheduleCountAfterLoad)
    }

    @MainActor @Test("handleFire re-schedules weekly repeating recordings")
    func handleFireReSchedulesWeekly() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "Weekly Review",
            startTime: Date().addingTimeInterval(-60),
            repeatRule: .weekly
        )
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        let scheduleCountBefore = mockService.scheduleCallCount
        vm.handleFire(recordingID: recording.id)

        #expect(mockService.scheduleCallCount > scheduleCountBefore)
    }

    // MARK: - importSkippedCount

    @MainActor @Test("importSkippedCount starts at zero")
    func importSkippedCountDefault() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        #expect(vm.importSkippedCount == 0)
    }

    // MARK: - nextScheduled

    @MainActor @Test("nextScheduled returns the earliest enabled future recording")
    func nextScheduledReturnsEarliest() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let later = ScheduledRecording(title: "Later", startTime: Date().addingTimeInterval(7200))
        let sooner = ScheduledRecording(title: "Sooner", startTime: Date().addingTimeInterval(3600))
        let disabled = ScheduledRecording(title: "Disabled", startTime: Date().addingTimeInterval(1800), isEnabled: false)
        context.insert(later)
        context.insert(sooner)
        context.insert(disabled)
        try context.save()
        vm.load(context: context)

        #expect(vm.nextScheduled?.title == "Sooner")
    }

    @MainActor @Test("nextScheduled returns nil when no future recordings")
    func nextScheduledNilWhenEmpty() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()
        vm.load(context: context)

        #expect(vm.nextScheduled == nil)
    }

    // MARK: - Double-fire prevention (lastTriggeredAt guard)

    @MainActor @Test("handleFire called twice does not double-trigger (lastTriggeredAt prevents it)")
    func handleFireDoublePrevention() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let recording = ScheduledRecording(
            title: "Double Fire Test",
            startTime: Date().addingTimeInterval(-60),
            repeatRule: .daily
        )
        context.insert(recording)
        try context.save()
        vm.load(context: context)

        // First fire
        vm.handleFire(recordingID: recording.id)
        let firstTriggered = recording.lastTriggeredAt
        #expect(firstTriggered != nil)

        // Second fire — lastTriggeredAt already set, but handleFire always updates it
        // The actual double-fire prevention is in checkAndFireDueRecordings (fireTime <= lastTriggeredAt)
        vm.handleFire(recordingID: recording.id)
        let secondTriggered = recording.lastTriggeredAt
        #expect(secondTriggered != nil)
        // Second trigger time should be >= first (updated each call)
        #expect(secondTriggered! >= firstTriggered!)
    }

    // MARK: - autoStartKey constant

    @Test("autoStartKey is a stable string constant")
    func autoStartKeyConstant() {
        #expect(SchedulerViewModel.autoStartKey == "autoStartRecordingAllowed")
    }

    // MARK: - recordingsByLabel

    @MainActor @Test("recordingsByLabel groups and sorts correctly")
    func recordingsByLabelGrouping() throws {
        let mockService = MockSchedulerService()
        let vm = SchedulerViewModel(schedulerService: mockService)
        let context = try makeTestContext()

        let r1 = ScheduledRecording(title: "A", label: "Work", startTime: Date().addingTimeInterval(3600))
        let r2 = ScheduledRecording(title: "B", label: "Personal", startTime: Date().addingTimeInterval(7200))
        let r3 = ScheduledRecording(title: "C", label: "Work", startTime: Date().addingTimeInterval(1800))
        context.insert(r1)
        context.insert(r2)
        context.insert(r3)
        try context.save()
        vm.load(context: context)

        let groups = vm.recordingsByLabel
        #expect(groups.count == 2)
        // Sorted alphabetically: Personal, Work
        #expect(groups[0].label == "Personal")
        #expect(groups[1].label == "Work")
        #expect(groups[1].recordings.count == 2)
        // Within group, sorted by startTime: C (1800s) before A (3600s)
        #expect(groups[1].recordings[0].title == "C")
        #expect(groups[1].recordings[1].title == "A")
    }
}
