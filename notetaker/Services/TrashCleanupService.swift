import Foundation
import SwiftData
import os

/// Handles automatic cleanup of expired trash sessions and permanent deletion.
nonisolated enum TrashCleanupService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "TrashCleanup")

    /// Permanently delete sessions that have been in trash longer than retentionDays.
    @MainActor
    static func cleanupExpired(context: ModelContext, retentionDays: Int = 30, now: Date = Date()) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else { return }

        do {
            let descriptor = FetchDescriptor<RecordingSession>(
                predicate: #Predicate { session in
                    session.deletedAt != nil
                }
            )
            let deleted = try context.fetch(descriptor)
            let expired = deleted.filter { session in
                guard let deletedAt = session.deletedAt else { return false }
                return deletedAt < cutoff
            }

            for session in expired {
                permanentlyDelete(session: session, context: context)
            }

            if !expired.isEmpty {
                try context.save()
                logger.info("Cleaned up \(expired.count) expired trash session(s)")
            }
        } catch {
            logger.error("Trash cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Permanently delete a single session and its audio files.
    @MainActor
    static func permanentlyDelete(session: RecordingSession, context: ModelContext) {
        // Delete audio files
        for url in session.audioFileURLs {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.warning("Failed to delete audio file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // SwiftData cascade deletes segments + summaries
        context.delete(session)
        logger.info("Permanently deleted session: \(session.title)")
    }
}
