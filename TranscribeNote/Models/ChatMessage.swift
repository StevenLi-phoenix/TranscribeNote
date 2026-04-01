import Foundation

/// An ephemeral chat message for transcript Q&A conversations.
/// Stored in memory only — not persisted with SwiftData.
nonisolated struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: LLMMessage.Role
    let content: String
    let timestamp: Date
    let isError: Bool

    init(
        id: UUID = UUID(),
        role: LLMMessage.Role,
        content: String,
        timestamp: Date = Date(),
        isError: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isError = isError
    }
}
