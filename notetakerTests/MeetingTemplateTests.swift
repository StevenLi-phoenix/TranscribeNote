import Testing
import Foundation
@testable import notetaker

@Suite("MeetingTemplate Tests")
struct MeetingTemplateTests {

    @Test("Built-in templates count is 5")
    func builtInCount() {
        let builtIns = MeetingTemplateStore.builtInTemplates
        #expect(builtIns.count == 5)
    }

    @Test("Built-in templates have stable UUIDs and isBuiltIn flag")
    func builtInProperties() {
        let builtIns = MeetingTemplateStore.builtInTemplates
        for template in builtIns {
            #expect(template.isBuiltIn == true)
            #expect(!template.name.isEmpty)
            #expect(!template.icon.isEmpty)
            #expect(!template.description.isEmpty)
        }
        // Verify stable UUIDs
        #expect(builtIns[0].id == UUID(uuidString: "A0000001-0000-0000-0000-000000000001")!)
        #expect(builtIns[1].id == UUID(uuidString: "A0000001-0000-0000-0000-000000000002")!)
    }

    @Test("loadTemplates returns built-ins on fresh state")
    func loadTemplatesReturnsBuiltIns() throws {
        // Use a temp URL to avoid touching real storage
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // loadTemplates always includes built-ins even if file doesn't exist
        let templates = MeetingTemplateStore.loadTemplates()
        #expect(templates.count >= 5)
        #expect(templates.filter(\.isBuiltIn).count == 5)
    }

    @Test("deleteTemplate does not delete built-in")
    func deleteBuiltInNoop() {
        var templates = MeetingTemplateStore.builtInTemplates
        let countBefore = templates.count
        MeetingTemplateStore.deleteTemplate(id: templates[0].id, from: &templates)
        #expect(templates.count == countBefore)
    }

    @Test("deleteTemplate removes custom template")
    func deleteCustomTemplate() {
        var templates = MeetingTemplateStore.builtInTemplates
        let custom = MeetingTemplate(name: "Custom", icon: "star", description: "Test")
        templates.append(custom)
        #expect(templates.count == 6)

        MeetingTemplateStore.deleteTemplate(id: custom.id, from: &templates)
        #expect(templates.count == 5)
        #expect(!templates.contains(where: { $0.id == custom.id }))
    }

    @Test("duplicateTemplate creates copy with new ID and name suffix")
    func duplicateTemplate() {
        let original = MeetingTemplateStore.builtInTemplates[0]
        let copy = MeetingTemplateStore.duplicateTemplate(original)

        #expect(copy.id != original.id)
        #expect(copy.name == "\(original.name) (Copy)")
        #expect(copy.icon == original.icon)
        #expect(copy.isBuiltIn == false)
        #expect(copy.summaryIntervalMinutes == original.summaryIntervalMinutes)
        #expect(copy.summaryStyle == original.summaryStyle)
    }

    @Test("JSON round-trip encoding and decoding")
    func jsonRoundTrip() throws {
        let template = MeetingTemplate(
            name: "Test",
            icon: "mic",
            description: "A test template",
            isBuiltIn: false,
            summaryIntervalMinutes: 10,
            summaryStyle: "bullets",
            language: "en",
            suggestedDurationMinutes: 30
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(MeetingTemplate.self, from: data)

        #expect(decoded.id == template.id)
        #expect(decoded.name == template.name)
        #expect(decoded.icon == template.icon)
        #expect(decoded.description == template.description)
        #expect(decoded.isBuiltIn == template.isBuiltIn)
        #expect(decoded.summaryIntervalMinutes == template.summaryIntervalMinutes)
        #expect(decoded.summaryStyle == template.summaryStyle)
        #expect(decoded.language == template.language)
        #expect(decoded.suggestedDurationMinutes == template.suggestedDurationMinutes)
    }

    @Test("Template with all optional fields nil")
    func allOptionalFieldsNil() throws {
        let template = MeetingTemplate(
            name: "Minimal",
            icon: "doc",
            description: "No overrides"
        )

        #expect(template.summaryIntervalMinutes == nil)
        #expect(template.summaryStyle == nil)
        #expect(template.language == nil)
        #expect(template.aiRecipeID == nil)
        #expect(template.llmProfileID == nil)
        #expect(template.suggestedDurationMinutes == nil)

        // Verify nil fields survive JSON round-trip
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(MeetingTemplate.self, from: data)
        #expect(decoded.summaryIntervalMinutes == nil)
        #expect(decoded.summaryStyle == nil)
        #expect(decoded.language == nil)
        #expect(decoded.aiRecipeID == nil)
        #expect(decoded.llmProfileID == nil)
        #expect(decoded.suggestedDurationMinutes == nil)
    }

    @Test("Template with all optional fields populated")
    func allOptionalFieldsPopulated() throws {
        let recipeID = UUID()
        let profileID = UUID()
        let template = MeetingTemplate(
            name: "Full",
            icon: "star.fill",
            description: "All fields set",
            isBuiltIn: false,
            summaryIntervalMinutes: 5,
            summaryStyle: "paragraph",
            language: "ja",
            aiRecipeID: recipeID,
            llmProfileID: profileID,
            suggestedDurationMinutes: 60
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(MeetingTemplate.self, from: data)

        #expect(decoded.summaryIntervalMinutes == 5)
        #expect(decoded.summaryStyle == "paragraph")
        #expect(decoded.language == "ja")
        #expect(decoded.aiRecipeID == recipeID)
        #expect(decoded.llmProfileID == profileID)
        #expect(decoded.suggestedDurationMinutes == 60)
    }

    @Test("MeetingTemplate conforms to Hashable")
    func hashableConformance() {
        let t1 = MeetingTemplate(name: "A", icon: "a", description: "a")
        let t2 = MeetingTemplate(name: "B", icon: "b", description: "b")
        let set: Set<MeetingTemplate> = [t1, t2, t1]
        #expect(set.count == 2)
    }

    @Test("Built-in General Meeting has expected config")
    func generalMeetingConfig() {
        let general = MeetingTemplateStore.builtInTemplates.first { $0.name == "General Meeting" }
        #expect(general != nil)
        #expect(general?.summaryIntervalMinutes == 10)
        #expect(general?.summaryStyle == "bullets")
        #expect(general?.suggestedDurationMinutes == nil)
    }

    @Test("Built-in Lecture template has expected config")
    func lectureTemplateConfig() {
        let lecture = MeetingTemplateStore.builtInTemplates.first { $0.name == "Lecture / Talk" }
        #expect(lecture != nil)
        #expect(lecture?.summaryIntervalMinutes == 30)
        #expect(lecture?.summaryStyle == "paragraph")
        #expect(lecture?.suggestedDurationMinutes == 60)
    }
}
