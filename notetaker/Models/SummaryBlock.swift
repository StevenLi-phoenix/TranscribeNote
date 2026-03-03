import Foundation
import SwiftData

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
    var isOverall: Bool = false
    var editedContent: String? = nil

    /// Returns edited content if available, otherwise the original generated content.
    var displayContent: String { editedContent ?? content }

    @Relationship(inverse: \RecordingSession.summaries)
    var session: RecordingSession?

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        coveringFrom: TimeInterval,
        coveringTo: TimeInterval,
        content: String,
        style: SummaryStyle = .bullets,
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
        self.style = style.rawValue
        self.model = model
        self.isPinned = isPinned
        self.userEdited = userEdited
        self.isOverall = isOverall
        self.editedContent = editedContent
    }

    var summaryStyle: SummaryStyle {
        SummaryStyle(rawValue: style) ?? .bullets
    }
}
