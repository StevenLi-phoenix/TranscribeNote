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

    @Relationship(deleteRule: .cascade)
    var segments: [TranscriptSegment]

    @Relationship(deleteRule: .cascade)
    var summaries: [SummaryBlock] = []

    @Relationship(deleteRule: .cascade)
    var actionItems: [ActionItem] = []

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
        actionItems: [ActionItem] = [],
        isPartial: Bool = false,
        scheduledRecordingID: UUID? = nil
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
        self.actionItems = actionItems
        self.isPartial = isPartial
        self.scheduledRecordingID = scheduledRecordingID
    }
}
