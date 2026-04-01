import Foundation
import SwiftData

/// SchemaV3 - Adds `ScheduledRecording` model for timed recording scheduling.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV3.RecordingSession.self,
            SchemaV3.TranscriptSegment.self,
            SchemaV3.SummaryBlock.self,
            SchemaV3.ScheduledRecording.self,
        ]
    }

    // MARK: - Existing models (unchanged from V2)

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

        @Relationship(inverse: \SchemaV3.RecordingSession.segments)
        var session: SchemaV3.RecordingSession?

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
        var style: String
        var model: String
        var isPinned: Bool
        var userEdited: Bool
        var isOverall: Bool = false
        var editedContent: String? = nil

        @Relationship(inverse: \SchemaV3.RecordingSession.summaries)
        var session: SchemaV3.RecordingSession?

        init(
            id: UUID = UUID(),
            generatedAt: Date = Date(),
            coveringFrom: TimeInterval,
            coveringTo: TimeInterval,
            content: String,
            style: String = "bullets",
            model: String = "",
            isPinned: Bool = false,
            userEdited: Bool = false,
            isOverall: Bool = false,
            editedContent: String? = nil
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
            self.editedContent = editedContent
        }
    }

    // MARK: - NEW in V3

    @Model
    final class ScheduledRecording {
        var id: UUID = UUID()
        var title: String = ""
        var label: String = ""
        var startTime: Date = Date()
        var durationMinutes: Int? = nil
        var repeatRule: String = "once"
        var reminderMinutes: Int = 1
        var isEnabled: Bool = true
        var lastTriggeredAt: Date? = nil

        init(
            id: UUID = UUID(),
            title: String = "",
            label: String = "",
            startTime: Date = Date(),
            durationMinutes: Int? = nil,
            repeatRule: String = "once",
            reminderMinutes: Int = 1,
            isEnabled: Bool = true,
            lastTriggeredAt: Date? = nil
        ) {
            self.id = id
            self.title = title
            self.label = label
            self.startTime = startTime
            self.durationMinutes = durationMinutes
            self.repeatRule = repeatRule
            self.reminderMinutes = reminderMinutes
            self.isEnabled = isEnabled
            self.lastTriggeredAt = lastTriggeredAt
        }
    }
}
