import Foundation

/// A reusable prompt template for different meeting types.
nonisolated struct AIRecipe: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var icon: String                    // SF Symbol name
    var promptTemplate: String          // supports {{transcript}}, {{duration}}, {{date}}, {{title}}
    var outputSections: [String]        // e.g. ["Action Items", "Decisions", "Follow-ups"]
    var summaryStyle: String            // "bullet" / "paragraph" / "detailed"
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String,
        promptTemplate: String,
        outputSections: [String] = [],
        summaryStyle: String = "bullet",
        isBuiltIn: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.promptTemplate = promptTemplate
        self.outputSections = outputSections
        self.summaryStyle = summaryStyle
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
