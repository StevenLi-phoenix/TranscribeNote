import Testing
import Foundation
import SwiftData
@testable import notetaker

@Suite("ActionItemMarkdownFormatter")
struct ActionItemMarkdownFormatterTests {

    private func makeItem(
        content: String,
        category: ActionItemCategory = .task,
        isCompleted: Bool = false,
        assignee: String? = nil,
        dueDate: Date? = nil
    ) -> ActionItem {
        ActionItem(
            content: content,
            isCompleted: isCompleted,
            dueDate: dueDate,
            assignee: assignee,
            category: category
        )
    }

    @Test("Format empty list returns empty string")
    func emptyList() {
        let result = ActionItemMarkdownFormatter.format(actionItems: [])
        #expect(result.isEmpty)
    }

    @Test("Format tasks with checkboxes")
    func tasksWithCheckboxes() {
        let items = [
            makeItem(content: "Review PR"),
            makeItem(content: "Fix bug", isCompleted: true),
        ]
        let result = ActionItemMarkdownFormatter.format(actionItems: items)
        #expect(result.contains("- [ ] Review PR"))
        #expect(result.contains("- [x] Fix bug"))
    }

    @Test("Group by category")
    func groupByCategory() {
        let items = [
            makeItem(content: "Do thing", category: .task),
            makeItem(content: "Decided X", category: .decision),
            makeItem(content: "Follow up", category: .followUp),
        ]
        let result = ActionItemMarkdownFormatter.format(actionItems: items)
        #expect(result.contains("### Tasks"))
        #expect(result.contains("### Decisions"))
        #expect(result.contains("### Follow-ups"))
    }

    @Test("Include assignee and due date")
    func includeMetadata() {
        let date = DateComponents(calendar: .current, year: 2026, month: 4, day: 1).date!
        let items = [
            makeItem(content: "Review", assignee: "Alice", dueDate: date),
        ]
        let result = ActionItemMarkdownFormatter.format(actionItems: items)
        #expect(result.contains("@Alice"))
        #expect(result.contains("due 2026-04-01"))
    }

    @Test("Skip empty categories")
    func skipEmptyCategories() {
        let items = [
            makeItem(content: "Only a task", category: .task),
        ]
        let result = ActionItemMarkdownFormatter.format(actionItems: items)
        #expect(result.contains("### Tasks"))
        #expect(!result.contains("### Decisions"))
        #expect(!result.contains("### Follow-ups"))
    }

    @Test("Heading is Action Items")
    func heading() {
        let items = [makeItem(content: "Something")]
        let result = ActionItemMarkdownFormatter.format(actionItems: items)
        #expect(result.hasPrefix("## Action Items"))
    }
}
