import Foundation
import SwiftData

/// SchemaV8 - Adds `structuredContent` to SummaryBlock for structured summary output.
enum SchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV8.RecordingSession.self,
            SchemaV8.TranscriptSegment.self,
            SchemaV8.SummaryBlock.self,
            SchemaV8.ScheduledRecording.self,
            SchemaV8.ActionItem.self,
        ]
    }

    // MARK: - SummaryBlock (modified: added structuredContent)

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
        /// JSON-encoded StructuredSummary for rich display (key points, action items, sentiment).
        var structuredContent: String? = nil

        @Relationship(inverse: \SchemaV8.RecordingSession.summaries)
        var session: SchemaV8.RecordingSession?

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
            editedContent: String? = nil,
            structuredContent: String? = nil
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
            self.structuredContent = structuredContent
        }
    }

    // MARK: - Unchanged from V7

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
        var scheduledRecordingID: UUID? = nil

        @Relationship(deleteRule: .cascade)
        var segments: [TranscriptSegment]

        @Relationship(deleteRule: .cascade)
        var summaries: [SummaryBlock] = []

        @Relationship(deleteRule: .cascade)
        var actionItems: [ActionItem] = []

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

    @Model
    final class ActionItem {
        var id: UUID
        var content: String
        var isCompleted: Bool = false
        var dueDate: Date? = nil
        var assignee: String? = nil
        var category: String = "task"
        var createdAt: Date = Date()

        @Relationship(inverse: \SchemaV8.RecordingSession.actionItems)
        var session: SchemaV8.RecordingSession?

        init(
            id: UUID = UUID(),
            content: String,
            isCompleted: Bool = false,
            dueDate: Date? = nil,
            assignee: String? = nil,
            category: String = "task",
            createdAt: Date = Date()
        ) {
            self.id = id
            self.content = content
            self.isCompleted = isCompleted
            self.dueDate = dueDate
            self.assignee = assignee
            self.category = category
            self.createdAt = createdAt
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

        @Relationship(inverse: \SchemaV8.RecordingSession.segments)
        var session: SchemaV8.RecordingSession?

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
