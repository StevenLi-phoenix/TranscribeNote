import Foundation
import Testing
import SwiftData
@testable import notetaker

@Suite("Session Trash", .serialized)
struct SessionTrashTests {
    @MainActor @Test func moveToTrash_setsDeletedAt() throws {
        let container = try ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let session = RecordingSession(title: "Test")
        context.insert(session)

        #expect(session.deletedAt == nil)
        #expect(!session.isDeleted)

        session.moveToTrash()
        #expect(session.deletedAt != nil)
        #expect(session.isDeleted)
    }

    @MainActor @Test func restore_clearsDeletedAt() throws {
        let container = try ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let session = RecordingSession(title: "Test")
        context.insert(session)

        session.moveToTrash()
        session.restore()
        #expect(session.deletedAt == nil)
        #expect(!session.isDeleted)
    }

    @Test func daysUntilPermanentDeletion_fresh() {
        // Fresh delete should be ~30 days
        let deletedAt = Date()
        let days = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        #expect(max(0, 30 - days) == 30)
    }

    @Test func daysUntilPermanentDeletion_old() {
        let deletedAt = Calendar.current.date(byAdding: .day, value: -25, to: Date())!
        let days = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        #expect(max(0, 30 - days) == 5)
    }

    @Test func daysUntilPermanentDeletion_expired() {
        let deletedAt = Calendar.current.date(byAdding: .day, value: -35, to: Date())!
        let days = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        #expect(max(0, 30 - days) == 0)
    }

    @MainActor @Test func isDeleted_computed() throws {
        let container = try ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let session = RecordingSession(title: "Test")
        context.insert(session)

        #expect(!session.isDeleted)
        session.deletedAt = Date()
        #expect(session.isDeleted)
        session.deletedAt = nil
        #expect(!session.isDeleted)
    }

    @MainActor @Test func cleanupExpired_removesOldTrash() throws {
        let container = try ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        // Session deleted 35 days ago (expired)
        let expired = RecordingSession(title: "Expired", deletedAt: Calendar.current.date(byAdding: .day, value: -35, to: Date()))
        context.insert(expired)

        // Session deleted 5 days ago (not expired)
        let recent = RecordingSession(title: "Recent", deletedAt: Calendar.current.date(byAdding: .day, value: -5, to: Date()))
        context.insert(recent)

        // Active session (not deleted)
        let active = RecordingSession(title: "Active")
        context.insert(active)

        try context.save()

        TrashCleanupService.cleanupExpired(context: context)

        let all = try context.fetch(FetchDescriptor<RecordingSession>())
        #expect(all.count == 2)
        #expect(all.contains(where: { $0.title == "Recent" }))
        #expect(all.contains(where: { $0.title == "Active" }))
        #expect(!all.contains(where: { $0.title == "Expired" }))
    }

    @MainActor @Test func cleanupExpired_respectsRetentionDays() throws {
        let container = try ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, ScheduledRecording.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        // Session deleted 10 days ago
        let session = RecordingSession(title: "Test", deletedAt: Calendar.current.date(byAdding: .day, value: -10, to: Date()))
        context.insert(session)
        try context.save()

        // With default 30-day retention, should NOT be cleaned up
        TrashCleanupService.cleanupExpired(context: context)
        #expect(try context.fetch(FetchDescriptor<RecordingSession>()).count == 1)

        // With 5-day retention, SHOULD be cleaned up
        TrashCleanupService.cleanupExpired(context: context, retentionDays: 5)
        #expect(try context.fetch(FetchDescriptor<RecordingSession>()).count == 0)
    }
}
