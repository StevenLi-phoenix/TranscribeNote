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
    /// JSON-encoded StructuredSummary for rich display (key points, action items, sentiment).
    var structuredContent: String? = nil

    /// Returns edited content if available, otherwise the original generated content.
    var displayContent: String { editedContent ?? content }

    /// Cached decoded structured summary, if available.
    @Transient private var _cachedStructuredSummary: StructuredSummary?
    @Transient private var _structuredSummaryCacheKey: String?

    var structuredSummary: StructuredSummary? {
        if _structuredSummaryCacheKey == structuredContent, _cachedStructuredSummary != nil || structuredContent == nil {
            return _cachedStructuredSummary
        }
        _structuredSummaryCacheKey = structuredContent
        guard let json = structuredContent else {
            _cachedStructuredSummary = nil
            return nil
        }
        let decoded = StructuredSummary.fromJSON(json)
        _cachedStructuredSummary = decoded
        return decoded
    }

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
        editedContent: String? = nil,
        structuredContent: String? = nil
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
        self.structuredContent = structuredContent
    }

    var summaryStyle: SummaryStyle {
        SummaryStyle(rawValue: style) ?? .bullets
    }
}
