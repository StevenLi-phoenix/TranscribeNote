import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var trashedSessions: [RecordingSession] = []
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var showEmptyConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if trashedSessions.isEmpty {
                ContentUnavailableView(
                    "Trash is Empty",
                    systemImage: "trash",
                    description: Text("Deleted sessions will appear here for 30 days.")
                )
            } else {
                List(selection: $selectedIDs) {
                    ForEach(trashedSessions) { session in
                        TrashRowView(session: session)
                            .tag(session.persistentModelID)
                            .contextMenu {
                                Button("Restore") {
                                    session.restore()
                                    refreshList()
                                }
                                .accessibilityLabel("Restore session")
                                Divider()
                                Button("Delete Permanently", role: .destructive) {
                                    TrashCleanupService.permanentlyDelete(session: session, context: modelContext)
                                    refreshList()
                                }
                                .accessibilityLabel("Delete session permanently")
                            }
                    }
                }
                .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                    Button("Restore Selected (\(ids.count))") {
                        restoreSelected(ids)
                    }
                    .accessibilityLabel("Restore \(ids.count) selected sessions")
                    Divider()
                    Button("Delete Permanently (\(ids.count))", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .accessibilityLabel("Delete \(ids.count) selected sessions permanently")
                } primaryAction: { ids in
                    restoreSelected(ids)
                }
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            if !trashedSessions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Empty Trash") {
                        showEmptyConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Empty trash")
                }
            }
        }
        .confirmationDialog("Empty Trash?", isPresented: $showEmptyConfirmation, titleVisibility: .visible) {
            Button("Delete All Permanently", role: .destructive) {
                emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(trashedSessions.count) session(s). This cannot be undone.")
        }
        .confirmationDialog("Delete Permanently?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                permanentlyDeleteSelected(selectedIDs)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear { refreshList() }
    }

    private func refreshList() {
        do {
            let descriptor = FetchDescriptor<RecordingSession>(
                predicate: #Predicate { $0.deletedAt != nil },
                sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
            )
            trashedSessions = try modelContext.fetch(descriptor)
        } catch {
            trashedSessions = []
        }
    }

    private func restoreSelected(_ ids: Set<PersistentIdentifier>) {
        for session in trashedSessions where ids.contains(session.persistentModelID) {
            session.restore()
        }
        refreshList()
    }

    private func permanentlyDeleteSelected(_ ids: Set<PersistentIdentifier>) {
        for session in trashedSessions where ids.contains(session.persistentModelID) {
            TrashCleanupService.permanentlyDelete(session: session, context: modelContext)
        }
        refreshList()
    }

    private func emptyTrash() {
        for session in trashedSessions {
            TrashCleanupService.permanentlyDelete(session: session, context: modelContext)
        }
        refreshList()
    }
}

private struct TrashRowView: View {
    let session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(session.title.isEmpty ? "Untitled" : session.title)
                .fontWeight(.medium)
            HStack(spacing: DS.Spacing.xs) {
                if let deletedAt = session.deletedAt {
                    Text("Deleted \(deletedAt, style: .relative) ago")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                if let days = session.daysUntilPermanentDeletion {
                    Text("\u{00b7}").foregroundStyle(.tertiary)
                    Text("\(days) day\(days == 1 ? "" : "s") remaining")
                        .font(DS.Typography.caption)
                        .foregroundStyle(days <= 7 ? .red : .secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
