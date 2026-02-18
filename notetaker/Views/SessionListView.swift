import SwiftUI
import SwiftData
import os

struct SessionListView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SessionListView")

    @Query(sort: \RecordingSession.startedAt, order: .reverse)
    private var sessions: [RecordingSession]

    @Environment(\.modelContext) private var modelContext
    @Binding var selectedSessionID: UUID?
    @State private var selectedSessionIDs: Set<UUID> = []

    @State private var groupedSessions: [(date: Date, sessions: [RecordingSession])] = []

    private func updateGroupedSessions() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }
        groupedSessions = grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, sessions: $0.value) }
    }

    var body: some View {
        sessionList
            .listStyle(.sidebar)
            .onDeleteCommand { deleteSessions(ids: selectedSessionIDs) }
            .onAppear { updateGroupedSessions() }
            .onChange(of: sessions) { updateGroupedSessions() }
            .onChange(of: selectedSessionIDs) { _, newValue in
                if newValue.count == 1 {
                    selectedSessionID = newValue.first
                } else if newValue.isEmpty {
                    selectedSessionID = nil
                }
            }
            .onChange(of: selectedSessionID) { _, newValue in
                if let id = newValue {
                    if selectedSessionIDs != [id] {
                        selectedSessionIDs = [id]
                    }
                } else if !selectedSessionIDs.isEmpty {
                    selectedSessionIDs = []
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "tray",
                        description: Text("Start a recording to create your first session")
                    )
                }
            }
    }

    private var sessionList: some View {
        List(selection: $selectedSessionIDs) {
            ForEach(groupedSessions, id: \.date) { group in
                Section(group.date.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(group.sessions, id: \.id) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                            .contextMenu {
                                deleteButton(for: [session.id])
                            }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                deleteButton(for: ids)
            }
        }
    }

    private func deleteButton(for ids: Set<UUID>) -> some View {
        let label = ids.count == 1 ? "Delete" : "Delete \(ids.count) Sessions"
        return Button(label, role: .destructive) {
            deleteSessions(ids: ids)
        }
    }

    private func deleteSessions(ids: Set<UUID>) {
        let count = ids.count
        for id in ids {
            if let session = sessions.first(where: { $0.id == id }) {
                if let audioURL = session.audioFileURL {
                    do {
                        try FileManager.default.removeItem(at: audioURL)
                    } catch {
                        Self.logger.warning("Failed to delete audio file \(audioURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                modelContext.delete(session)
            }
        }
        do {
            try modelContext.save()
            Self.logger.info("Deleted \(count) session(s)")
        } catch {
            Self.logger.error("Failed to delete sessions: \(error.localizedDescription)")
        }

        if let selectedID = selectedSessionID, ids.contains(selectedID) {
            selectedSessionID = nil
        }
        selectedSessionIDs.subtract(ids)
    }
}

private struct SessionRowView: View {
    let session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.totalDuration > 0 {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(session.totalDuration.compactDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [session.title, session.startedAt.formatted(date: .omitted, time: .shortened)]
        if session.totalDuration > 0 {
            parts.append(session.totalDuration.compactDuration)
        }
        return parts.joined(separator: ", ")
    }
}
