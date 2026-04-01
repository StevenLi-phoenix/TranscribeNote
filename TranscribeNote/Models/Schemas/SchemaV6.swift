import Foundation
import SwiftData

/// SchemaV6 - Adds `calendarEventIdentifier` to ScheduledRecording and `scheduledRecordingID` to RecordingSession.
enum SchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV6.RecordingSession.self,
            SchemaV6.TranscriptSegment.self,
            SchemaV6.SummaryBlock.self,
            SchemaV6.ScheduledRecording.self,
        ]
    }

    // MARK: - RecordingSession (modified: added scheduledRecordingID)

    @Model
    final class RecordingSession {
        var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var title: String
        var audioFilePath: String?
        var audioFilePaths: [String] = []
        var tags: [String]
        var isPartial: Bool = false
        /// Links session to the triggering scheduled recording.
        var scheduledRecordingID: UUID? = nil

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
            audioFilePaths: [String] = [],
            tags: [String] = [],
            segments: [TranscriptSegment] = [],
            summaries: [SummaryBlock] = [],
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
            self.isPartial = isPartial
            self.scheduledRecordingID = scheduledRecordingID
        }
    }

    // MARK: - Unchanged from V5

    @Model
    final class TranscriptSegment {
        var id: UUID
        var startTime: TimeInterval
        var endTime: TimeInterval
        var text: String
        var confidence: Double
        var language: String?
        var speakerLabel: String?

        @Relationship(inverse: \SchemaV6.RecordingSession.segments)
        var session: SchemaV6.RecordingSession?

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

        @Relationship(inverse: \SchemaV6.RecordingSession.summaries)
        var session: SchemaV6.RecordingSession?

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

    // MARK: - ScheduledRecording (modified: added calendarEventIdentifier)

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
        /// EKEvent.eventIdentifier for robust calendar dedup.
        var calendarEventIdentifier: String? = nil

        init(
            id: UUID = UUID(),
            title: String = "",
            label: String = "",
            startTime: Date = Date(),
            durationMinutes: Int? = nil,
            repeatRule: String = "once",
            reminderMinutes: Int = 1,
            isEnabled: Bool = true,
            lastTriggeredAt: Date? = nil,
            calendarEventIdentifier: String? = nil
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
            self.calendarEventIdentifier = calendarEventIdentifier
        }
    }
}
