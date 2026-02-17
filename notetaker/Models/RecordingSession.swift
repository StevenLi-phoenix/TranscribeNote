import Foundation
import SwiftData

@Model
final class RecordingSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var title: String
    var audioFilePath: String?
    var tags: [String]

    @Relationship(deleteRule: .cascade)
    var segments: [TranscriptSegment]

    var audioFileURL: URL? {
        guard let audioFilePath else { return nil }
        guard let dir = try? AudioCaptureService.recordingsDirectory() else { return nil }
        return dir.appendingPathComponent(audioFilePath)
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
        tags: [String] = [],
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.audioFilePath = audioFilePath
        self.tags = tags
        self.segments = segments
    }
}
