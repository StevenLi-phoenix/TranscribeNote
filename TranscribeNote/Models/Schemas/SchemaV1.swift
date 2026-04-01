import Foundation
import SwiftData

/// SchemaV1 - Initial versioned schema snapshot
///
/// This is a snapshot of the current production schema. When we add V2, we'll:
/// 1. Keep this V1 snapshot unchanged
/// 2. Create SchemaV2 with the new schema
/// 3. Add migration stages to TranscribeNoteMigrationPlan
///
/// NOTE: Versioned schemas contain ONLY stored properties. Computed properties
/// (like RecordingSession.audioFileURL, RecordingSession.totalDuration) must
/// be removed from these snapshots.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SchemaV1.RecordingSession.self, SchemaV1.TranscriptSegment.self, SchemaV1.SummaryBlock.self]
    }

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

        @Relationship(deleteRule: .cascade)
        var summaries: [SummaryBlock] = []

        init(
            id: UUID = UUID(),
            startedAt: Date = Date(),
            endedAt: Date? = nil,
            title: String = "",
            audioFilePath: String? = nil,
            tags: [String] = [],
            segments: [TranscriptSegment] = [],
            summaries: [SummaryBlock] = []
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.title = title
            self.audioFilePath = audioFilePath
            self.tags = tags
            self.segments = segments
            self.summaries = summaries
        }
    }

    @Model
    final class TranscriptSegment {
        var id: UUID
        var startTime: TimeInterval
        var endTime: TimeInterval
        var text: String
        var confidence: Double
        var language: String?
        var speakerLabel: String?

        @Relationship(inverse: \SchemaV1.RecordingSession.segments)
        var session: SchemaV1.RecordingSession?

        init(
            id: UUID = UUID(),
            startTime: TimeInterval,
            endTime: TimeInterval,
            text: String,
            confidence: Double = 1.0,
            language: String? = nil,
            speakerLabel: String? = nil
        ) {
            self.id = id
            self.startTime = startTime
            self.endTime = endTime
            self.text = text
            self.confidence = confidence
            self.language = language
            self.speakerLabel = speakerLabel
        }
    }

    @Model
    final class SummaryBlock {
        var id: UUID
        var generatedAt: Date
        var coveringFrom: TimeInterval
        var coveringTo: TimeInterval
        var content: String
        var style: String  // SummaryStyle raw value stored as String for SwiftData
        var model: String
        var isPinned: Bool
        var userEdited: Bool
        var isOverall: Bool

        @Relationship(inverse: \SchemaV1.RecordingSession.summaries)
        var session: SchemaV1.RecordingSession?

        init(
            id: UUID = UUID(),
            generatedAt: Date = Date(),
            coveringFrom: TimeInterval,
            coveringTo: TimeInterval,
            content: String,
            style: String = "bullets",  // SummaryStyle.bullets.rawValue
            model: String = "",
            isPinned: Bool = false,
            userEdited: Bool = false,
            isOverall: Bool = false
        ) {
            self.id = id
            self.generatedAt = generatedAt
            self.coveringFrom = coveringFrom
            self.coveringTo = coveringTo
            self.content = content
            self.style = style
            self.model = model
            self.isPinned = isPinned
            self.userEdited = userEdited
            self.isOverall = isOverall
        }
    }
}
