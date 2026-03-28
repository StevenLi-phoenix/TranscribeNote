import Testing
import SwiftData
import Foundation
@testable import notetaker

@Suite("Pin/Favorite Sessions")
struct PinFavoriteTests {
    @Test func isPinned_defaultsToFalse() {
        let session = RecordingSession()
        #expect(session.isPinned == false)
    }

    @Test func pinnedAt_defaultsToNil() {
        let session = RecordingSession()
        #expect(session.pinnedAt == nil)
    }

    @Test func togglePin_setsIsPinnedAndPinnedAt() {
        let session = RecordingSession(title: "Test")

        // Initially unpinned
        #expect(session.isPinned == false)
        #expect(session.pinnedAt == nil)

        // Pin
        session.togglePin()
        #expect(session.isPinned == true)
        #expect(session.pinnedAt != nil)

        // Unpin
        session.togglePin()
        #expect(session.isPinned == false)
        #expect(session.pinnedAt == nil)
    }

    @Test func togglePin_updatesTimestamp() {
        let session = RecordingSession(title: "Timestamp Test")
        let before = Date()
        session.togglePin()
        let after = Date()

        guard let pinnedAt = session.pinnedAt else {
            Issue.record("pinnedAt should not be nil after toggling pin on")
            return
        }
        #expect(pinnedAt >= before)
        #expect(pinnedAt <= after)
    }

    @Test func initWithPinnedParameters() {
        let pinDate = Date()
        let session = RecordingSession(
            title: "Pinned Session",
            isPinned: true,
            pinnedAt: pinDate
        )
        #expect(session.isPinned == true)
        #expect(session.pinnedAt == pinDate)
    }

    @MainActor @Test func togglePin_persistsInSwiftData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self,
            configurations: config
        )
        let context = ModelContext(container)

        let session = RecordingSession(title: "Persist Test")
        context.insert(session)
        try context.save()

        session.togglePin()
        try context.save()

        let descriptor = FetchDescriptor<RecordingSession>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.isPinned == true)
        #expect(fetched.first?.pinnedAt != nil)
    }
}
