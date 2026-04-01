import Testing
import Foundation
import SwiftData
@testable import TranscribeNote

/// Tests for `BackgroundSummaryService` — task lifecycle, double-dispatch prevention,
/// cancellation, and await behavior.
///
/// All tests use `@MainActor` because `BackgroundSummaryService` is MainActor-isolated.
/// The suite is `.serialized` because it operates on the singleton `BackgroundSummaryService.shared`.
@Suite("BackgroundSummaryService Tests", .serialized)
struct BackgroundSummaryServiceTests {

    /// Shared reference to the singleton under test.
    /// Accessed only from @MainActor test methods via explicit MainActor.assumeIsolated.
    @MainActor private var service: BackgroundSummaryService { BackgroundSummaryService.shared }

    /// Create an in-memory SwiftData container for testing.
    @MainActor
    private func makeTestContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self,
            configurations: config
        )
    }

    /// Insert a session with segments into the container's main context.
    @MainActor
    private func insertSession(
        id: UUID = UUID(),
        container: ModelContainer,
        segmentCount: Int = 3
    ) throws -> RecordingSession {
        let context = container.mainContext
        let session = RecordingSession(
            id: id,
            startedAt: Date().addingTimeInterval(-300),
            endedAt: Date(),
            title: ""
        )
        context.insert(session)

        for i in 0..<segmentCount {
            let start = TimeInterval(i * 10)
            let end = start + 10
            let text = String(repeating: "word ", count: 30) // > minTranscriptLength
            let segment = TranscriptSegment(startTime: start, endTime: end, text: text)
            segment.session = session
            context.insert(segment)
        }

        try context.save()
        return session
    }

    // MARK: - isRunning

    @MainActor @Test("isRunning returns false for unknown UUID")
    func isRunningUnknownID() {
        let randomID = UUID()
        #expect(service.isRunning(for: randomID) == false)
    }

    @MainActor @Test("isRunning returns false after cancelAll clears tasks")
    func isRunningAfterCancelAll() throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session.id, container: container)
        #expect(service.isRunning(for: session.id) == true)

        service.cancelAll()
        #expect(service.isRunning(for: session.id) == false)
    }

    // MARK: - cancelAll

    @MainActor @Test("cancelAll on empty activeTasks does not crash")
    func cancelAllEmpty() {
        // Ensure clean state
        service.cancelAll()
        // Call again on already-empty state
        service.cancelAll()
        #expect(service.activeTasks.isEmpty)
    }

    @MainActor @Test("cancelAll removes all active tasks")
    func cancelAllRemovesTasks() throws {
        let container = try makeTestContainer()
        let session1 = try insertSession(container: container)
        let session2 = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session1.id, container: container)
        service.dispatchOverallSummary(sessionID: session2.id, container: container)

        #expect(service.activeTasks.count == 2)

        service.cancelAll()
        #expect(service.activeTasks.isEmpty)
    }

    // MARK: - awaitAll

    @MainActor @Test("awaitAll returns immediately when no tasks are active")
    func awaitAllEmpty() async {
        service.cancelAll()
        await service.awaitAll()
        #expect(service.activeTasks.isEmpty)
    }

    @MainActor @Test("awaitAll waits for dispatched tasks to complete")
    func awaitAllWaitsForCompletion() async throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session.id, container: container)
        #expect(service.isRunning(for: session.id) == true)

        await service.awaitAll()
        // After awaitAll, the task should have completed and removed itself from activeTasks
        #expect(service.isRunning(for: session.id) == false)
    }

    // MARK: - Double-dispatch prevention

    @MainActor @Test("dispatchOverallSummary does not create duplicate task for same sessionID")
    func doubleDispatchPrevention() throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session.id, container: container)
        #expect(service.activeTasks[session.id] != nil)

        // Dispatch again with same sessionID — should be a no-op (count stays 1)
        service.dispatchOverallSummary(sessionID: session.id, container: container)
        #expect(service.activeTasks.count == 1)

        // Cleanup
        service.cancelAll()
    }

    @MainActor @Test("dispatchOverallSummary allows different sessionIDs concurrently")
    func differentSessionsDispatchConcurrently() throws {
        let container = try makeTestContainer()
        let session1 = try insertSession(container: container)
        let session2 = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session1.id, container: container)
        service.dispatchOverallSummary(sessionID: session2.id, container: container)

        #expect(service.isRunning(for: session1.id) == true)
        #expect(service.isRunning(for: session2.id) == true)
        #expect(service.activeTasks.count == 2)

        // Cleanup
        service.cancelAll()
    }

    // MARK: - Task self-cleanup

    @MainActor @Test("task removes itself from activeTasks upon completion")
    func taskSelfCleanup() async throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session.id, container: container)
        #expect(service.isRunning(for: session.id) == true)

        // Wait for the task to finish (will likely fail LLM call but still cleans up)
        await service.awaitAll()

        #expect(service.isRunning(for: session.id) == false)
        #expect(service.activeTasks[session.id] == nil)
    }

    @MainActor @Test("task removes itself from activeTasks even when LLM fails")
    func taskCleansUpOnError() async throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session.id, container: container)

        // Let the task run to completion (LLM will fail since no real server)
        await service.awaitAll()

        // Task should have cleaned up regardless of error
        #expect(service.activeTasks.isEmpty)
    }

    // MARK: - Empty session handling

    @MainActor @Test("dispatchOverallSummary for nonexistent session cleans up task")
    func nonexistentSessionCleansUp() async throws {
        let container = try makeTestContainer()
        let fakeID = UUID()

        service.dispatchOverallSummary(sessionID: fakeID, container: container)
        #expect(service.isRunning(for: fakeID) == true)

        await service.awaitAll()

        // Task should have cleaned up after failing to find the session
        #expect(service.isRunning(for: fakeID) == false)
    }

    @MainActor @Test("dispatchOverallSummary for session with no segments cleans up task")
    func emptySegmentsCleansUp() async throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container, segmentCount: 0)

        service.dispatchOverallSummary(sessionID: session.id, container: container)

        await service.awaitAll()

        // Task should have cleaned up after seeing empty segments
        #expect(service.isRunning(for: session.id) == false)
    }

    // MARK: - Re-dispatch after completion

    @MainActor @Test("can dispatch again for same sessionID after previous task completes")
    func reDispatchAfterCompletion() async throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container)

        // First dispatch
        service.dispatchOverallSummary(sessionID: session.id, container: container)
        await service.awaitAll()
        #expect(service.isRunning(for: session.id) == false)

        // Second dispatch should succeed (not blocked by previous)
        service.dispatchOverallSummary(sessionID: session.id, container: container)
        #expect(service.isRunning(for: session.id) == true)

        // Cleanup
        service.cancelAll()
    }

    // MARK: - Cancellation behavior

    @MainActor @Test("cancelled task cleans up after awaitAll")
    func cancelledTaskCleanup() async throws {
        let container = try makeTestContainer()
        let session = try insertSession(container: container)

        service.dispatchOverallSummary(sessionID: session.id, container: container)
        service.cancelAll()

        // activeTasks is already cleared by cancelAll
        #expect(service.activeTasks.isEmpty)
    }
}
