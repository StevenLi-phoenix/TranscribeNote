import Foundation

/// Formats action items as a Markdown checklist grouped by category.
enum ActionItemMarkdownFormatter {
    static func format(actionItems: [ActionItem]) -> String {
        guard !actionItems.isEmpty else { return "" }

        var sections: [String] = ["## Action Items"]

        let grouped = Dictionary(grouping: actionItems) { $0.itemCategory }

        let categoryOrder: [(ActionItemCategory, String)] = [
            (.task, "Tasks"),
            (.decision, "Decisions"),
            (.followUp, "Follow-ups"),
        ]

        for (category, heading) in categoryOrder {
            guard let items = grouped[category], !items.isEmpty else { continue }
            sections.append("\n### \(heading)")
            for item in items {
                let checkbox = item.isCompleted ? "[x]" : "[ ]"
                var line = "- \(checkbox) \(item.content)"
                var meta: [String] = []
                if let assignee = item.assignee, !assignee.isEmpty {
                    meta.append("@\(assignee)")
                }
                if let dueDate = item.dueDate {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    meta.append("due \(formatter.string(from: dueDate))")
                }
                if !meta.isEmpty {
                    line += " (\(meta.joined(separator: ", ")))"
                }
                sections.append(line)
            }
        }

        return sections.joined(separator: "\n")
    }
}
