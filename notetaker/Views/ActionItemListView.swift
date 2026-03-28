import SwiftUI
import SwiftData
import os

/// Displays action items as a grouped checklist in a popover.
struct ActionItemListView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ActionItemListView")

    let actionItems: [ActionItem]
    let sessionTitle: String
    let onExportReminders: () -> Void
    let onExportCalendar: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var copyFeedback = false

    private var hasDueDates: Bool {
        actionItems.contains { $0.dueDate != nil && !$0.isCompleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with export menu
            HStack {
                Text("Action Items")
                    .font(DS.Typography.sectionHeader)

                Text("\(actionItems.count)")
                    .font(DS.Typography.caption2)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Spacer()

                Menu {
                    Button {
                        copyAsMarkdown()
                    } label: {
                        Label(copyFeedback ? "Copied!" : "Copy as Markdown", systemImage: copyFeedback ? "checkmark" : "doc.on.doc")
                    }
                    Divider()
                    Button {
                        onExportReminders()
                    } label: {
                        Label("Export to Reminders", systemImage: "checklist")
                    }
                    if hasDueDates {
                        Button {
                            onExportCalendar()
                        } label: {
                            Label("Export to Calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    let grouped = Dictionary(grouping: actionItems) { $0.itemCategory }
                    let categoryOrder: [(ActionItemCategory, String, String)] = [
                        (.task, "Tasks", "checklist"),
                        (.decision, "Decisions", "checkmark.seal"),
                        (.followUp, "Follow-ups", "arrow.uturn.forward"),
                    ]

                    ForEach(categoryOrder, id: \.0) { category, heading, icon in
                        if let items = grouped[category], !items.isEmpty {
                            categorySection(heading: heading, icon: icon, items: items)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
            }
        }
    }

    private func categorySection(heading: String, icon: String, items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Label(heading, systemImage: icon)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

            ForEach(items) { item in
                actionItemRow(item)
            }
        }
    }

    private func actionItemRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Button {
                item.isCompleted.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(item.content)
                    .font(DS.Typography.callout)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: DS.Spacing.sm) {
                    if let assignee = item.assignee, !assignee.isEmpty {
                        Label(assignee, systemImage: "person")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let dueDate = item.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(dueDate < Date() && !item.isCompleted ? DS.Colors.subtleError : .secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, DS.Spacing.xxs)
        .padding(.horizontal, DS.Spacing.sm)
        .contextMenu {
            if item.dueDate == nil {
                Button("Set Due Date to Tomorrow") {
                    item.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                    try? modelContext.save()
                }
                Button("Set Due Date to Next Week") {
                    item.dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())
                    try? modelContext.save()
                }
            } else {
                Button("Clear Due Date") {
                    item.dueDate = nil
                    try? modelContext.save()
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
            }
        }
    }

    private func copyAsMarkdown() {
        let markdown = ActionItemMarkdownFormatter.format(actionItems: actionItems)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        Self.logger.info("Copied \(actionItems.count) action items as markdown")
        copyFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copyFeedback = false
        }
    }
}
