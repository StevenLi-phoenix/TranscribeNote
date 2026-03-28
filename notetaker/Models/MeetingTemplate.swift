import Foundation

/// A reusable meeting workflow preset that configures recording, summarization, and automation.
nonisolated struct MeetingTemplate: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var icon: String  // SF Symbol name
    var description: String
    var isBuiltIn: Bool

    // Summarization overrides
    var summaryIntervalMinutes: Int?  // Override periodic summary interval
    var summaryStyle: String?         // SummaryStyle raw value
    var language: String?             // Override language

    // Optional linked IDs (resolved at apply time if features available)
    var aiRecipeID: UUID?
    var llmProfileID: UUID?

    // Recording hints
    var suggestedDurationMinutes: Int?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        description: String,
        isBuiltIn: Bool = false,
        summaryIntervalMinutes: Int? = nil,
        summaryStyle: String? = nil,
        language: String? = nil,
        aiRecipeID: UUID? = nil,
        llmProfileID: UUID? = nil,
        suggestedDurationMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.isBuiltIn = isBuiltIn
        self.summaryIntervalMinutes = summaryIntervalMinutes
        self.summaryStyle = summaryStyle
        self.language = language
        self.aiRecipeID = aiRecipeID
        self.llmProfileID = llmProfileID
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
