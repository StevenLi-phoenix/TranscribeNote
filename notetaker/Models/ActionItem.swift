import Foundation
import SwiftData

/// Category of an extracted action item.
nonisolated enum ActionItemCategory: String, Codable, CaseIterable, Sendable {
    case task
    case decision
    case followUp
}

@Model
final class ActionItem {
    var id: UUID
    var content: String
    var isCompleted: Bool = false
    var dueDate: Date? = nil
    var assignee: String? = nil
    /// Stored as `ActionItemCategory.rawValue` (SwiftData can't store custom enums directly).
    var category: String = "task"
    var createdAt: Date = Date()

    @Relationship(inverse: \RecordingSession.actionItems)
    var session: RecordingSession?

    /// Typed accessor for `category`.
    var itemCategory: ActionItemCategory {
        ActionItemCategory(rawValue: category) ?? .task
    }

    init(
        id: UUID = UUID(),
        content: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        assignee: String? = nil,
        category: ActionItemCategory = .task,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.assignee = assignee
        self.category = category.rawValue
        self.createdAt = createdAt
    }
}
