import Foundation
import os

/// Manages persistence and CRUD for meeting templates.
/// Built-in templates are always present; custom templates stored as JSON.
nonisolated enum MeetingTemplateStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "MeetingTemplateStore"
    )

    static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("notetaker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("templates.json")
    }

    // MARK: - CRUD

    static func loadTemplates() -> [MeetingTemplate] {
        var templates = loadFromFile()
        // Ensure built-ins are present
        for builtIn in builtInTemplates {
            if !templates.contains(where: { $0.id == builtIn.id }) {
                templates.insert(builtIn, at: 0)
            }
        }
        logger.debug("Loaded \(templates.count) meeting templates")
        return templates.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.name < rhs.name
        }
    }

    static func saveTemplates(_ templates: [MeetingTemplate]) {
        do {
            let data = try JSONEncoder().encode(templates)
            try data.write(to: storageURL, options: .atomic)
            logger.info("Saved \(templates.count) meeting templates")
        } catch {
            logger.error("Failed to save meeting templates: \(error.localizedDescription)")
        }
    }

    static func deleteTemplate(id: UUID, from templates: inout [MeetingTemplate]) {
        templates.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    static func duplicateTemplate(_ template: MeetingTemplate) -> MeetingTemplate {
        MeetingTemplate(
            name: "\(template.name) (Copy)",
            icon: template.icon,
            description: template.description,
            isBuiltIn: false,
            summaryIntervalMinutes: template.summaryIntervalMinutes,
            summaryStyle: template.summaryStyle,
            language: template.language,
            aiRecipeID: template.aiRecipeID,
            llmProfileID: template.llmProfileID,
            suggestedDurationMinutes: template.suggestedDurationMinutes
        )
    }

    // MARK: - Private

    private static func loadFromFile() -> [MeetingTemplate] {
        guard let data = try? Data(contentsOf: storageURL),
              let templates = try? JSONDecoder().decode([MeetingTemplate].self, from: data) else {
            return []
        }
        return templates
    }

    // MARK: - Built-in Templates (stable UUIDs)

    static let builtInTemplates: [MeetingTemplate] = [
        MeetingTemplate(
            id: UUID(uuidString: "A0000001-0000-0000-0000-000000000001")!,
            name: "General Meeting",
            icon: "person.3",
            description: "Standard meeting with key points, decisions, and action items",
            isBuiltIn: true,
            summaryIntervalMinutes: 10,
            summaryStyle: "bullets"
        ),
        MeetingTemplate(
            id: UUID(uuidString: "A0000001-0000-0000-0000-000000000002")!,
            name: "Standup / Sync",
            icon: "list.clipboard",
            description: "Quick sync with blockers and action items (15-30 min)",
            isBuiltIn: true,
            summaryIntervalMinutes: 5,
            summaryStyle: "bullets",
            suggestedDurationMinutes: 15
        ),
        MeetingTemplate(
            id: UUID(uuidString: "A0000001-0000-0000-0000-000000000003")!,
            name: "1-on-1",
            icon: "person.2",
            description: "One-on-one with status, blockers, and career development",
            isBuiltIn: true,
            summaryIntervalMinutes: 15,
            summaryStyle: "bullets",
            suggestedDurationMinutes: 30
        ),
        MeetingTemplate(
            id: UUID(uuidString: "A0000001-0000-0000-0000-000000000004")!,
            name: "Brainstorm",
            icon: "lightbulb",
            description: "Creative session — capture ideas, group themes, identify next steps",
            isBuiltIn: true,
            summaryIntervalMinutes: 15,
            summaryStyle: "actionItems"
        ),
        MeetingTemplate(
            id: UUID(uuidString: "A0000001-0000-0000-0000-000000000005")!,
            name: "Lecture / Talk",
            icon: "graduationcap",
            description: "Long-form content — larger summary chunks, detailed notes",
            isBuiltIn: true,
            summaryIntervalMinutes: 30,
            summaryStyle: "paragraph",
            suggestedDurationMinutes: 60
        ),
    ]
}
