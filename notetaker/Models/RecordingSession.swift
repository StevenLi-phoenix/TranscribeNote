import Foundation
import SwiftData

@Model
final class RecordingSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var title: String
    var audioFilePath: String?
    var audioFilePaths: [String] = []
    var tags: [String]
    /// True if session was saved during force-quit (transcript may be incomplete).
    var isPartial: Bool = false
    /// Links session to the triggering scheduled recording.
    var scheduledRecordingID: UUID? = nil
    /// Whether this session is pinned/favorited.
    var isPinned: Bool = false
    /// When the session was pinned (for sort ordering).
    var pinnedAt: Date? = nil
    /// When the session was moved to trash (nil = not deleted).
    var deletedAt: Date? = nil

    @Relationship(deleteRule: .cascade)
    var segments: [TranscriptSegment]

    @Relationship(deleteRule: .cascade)
    var summaries: [SummaryBlock] = []

    /// All audio file URLs for this session (supports multi-clip pause/resume).
    /// Falls back to legacy single `audioFilePath` for older sessions.
    var audioFileURLs: [URL] {
        guard let dir = try? AudioCaptureService.recordingsDirectory() else { return [] }
        if !audioFilePaths.isEmpty {
            return audioFilePaths.map { dir.appendingPathComponent($0) }
        }
        if let audioFilePath {
            return [dir.appendingPathComponent(audioFilePath)]
        }
        return []
    }

    /// First audio file URL (backward-compatible convenience).
    var audioFileURL: URL? {
        audioFileURLs.first
    }

    var totalDuration: TimeInterval {
        guard let endedAt else { return 0 }
        return endedAt.timeIntervalSince(startedAt)
    }

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        title: String = "",
        audioFilePath: String? = nil,
        audioFilePaths: [String] = [],
        tags: [String] = [],
        segments: [TranscriptSegment] = [],
        summaries: [SummaryBlock] = [],
        isPartial: Bool = false,
        scheduledRecordingID: UUID? = nil,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.audioFilePath = audioFilePath
        self.audioFilePaths = audioFilePaths
        self.tags = tags
        self.segments = segments
        self.summaries = summaries
        self.isPartial = isPartial
        self.scheduledRecordingID = scheduledRecordingID
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.deletedAt = deletedAt
    }

    // MARK: - Trash

    var isDeleted: Bool { deletedAt != nil }

    func moveToTrash() {
        deletedAt = Date()
    }

    func restore() {
        deletedAt = nil
    }

    /// Days remaining before automatic permanent deletion (30-day retention).
    var daysUntilPermanentDeletion: Int? {
        guard let deletedAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        return max(0, 30 - days)
    }

    func togglePin() {
        isPinned.toggle()
        pinnedAt = isPinned ? Date() : nil
    }
}
