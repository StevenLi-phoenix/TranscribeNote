import SwiftUI
import SwiftData
import os

enum DateFilter: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
}

struct SessionListView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SessionListView")

    @Query(sort: \RecordingSession.startedAt, order: .reverse)
    private var sessions: [RecordingSession]

    @Environment(\.modelContext) private var modelContext
    @Binding var selectedSessionID: UUID?
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var dateFilter: DateFilter = .all
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var sessionsToDelete: Set<UUID> = []
    @State private var showDeleteConfirmation = false

    @State private var groupedSessions: [(date: Date, sessions: [RecordingSession])] = []

    /// All non-deleted sessions (excludes trash).
    private var activeSessions: [RecordingSession] {
        sessions.filter { $0.deletedAt == nil }
    }

    private var filteredSessions: [RecordingSession] {
        var result = activeSessions

        // Date filter
        if dateFilter != .all {
            let calendar = Calendar.current
            let now = Date()
            result = result.filter { session in
                switch dateFilter {
                case .today:
                    return calendar.isDateInToday(session.startedAt)
                case .thisWeek:
                    return calendar.isDate(session.startedAt, equalTo: now, toGranularity: .weekOfYear)
                case .thisMonth:
                    return calendar.isDate(session.startedAt, equalTo: now, toGranularity: .month)
                case .all:
                    return true
                }
            }
        }

        // Text search
        if !searchText.isEmpty {
            let query = searchText
            result = result.filter { session in
                if session.title.localizedCaseInsensitiveContains(query) { return true }
                if session.segments.contains(where: { $0.text.localizedCaseInsensitiveContains(query) }) { return true }
                if session.summaries.contains(where: { $0.content.localizedCaseInsensitiveContains(query) }) { return true }
                return false
            }
        }

        return result
    }

    private func updateGroupedSessions() {
        let calendar = Calendar.current
        let filtered = filteredSessions
        let grouped = Dictionary(grouping: filtered) { session in
            calendar.startOfDay(for: session.startedAt)
        }
        groupedSessions = grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, sessions: $0.value) }
    }

    var body: some View {
        sessionList
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search sessions...")
            .onDeleteCommand {
                sessionsToDelete = selectedSessionIDs
                showDeleteConfirmation = true
            }
            .confirmationDialog(
                "Delete \(sessionsToDelete.count == 1 ? "Session" : "\(sessionsToDelete.count) Sessions")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteSessions(ids: sessionsToDelete)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if UserDefaults.standard.bool(forKey: "skipTrashOnDelete") {
                    Text("This will permanently delete the recording\(sessionsToDelete.count == 1 ? "" : "s") and associated audio files.")
                } else {
                    Text("The recording\(sessionsToDelete.count == 1 ? "" : "s") will be moved to Trash and permanently deleted after 30 days.")
                }
            }
            .onAppear { updateGroupedSessions() }
            .onChange(of: sessions) { updateGroupedSessions() }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                if newValue.isEmpty {
                    updateGroupedSessions()
                } else {
                    searchDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        withAnimation { updateGroupedSessions() }
                    }
                }
            }
            .onChange(of: dateFilter) { withAnimation { updateGroupedSessions() } }
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
                if activeSessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "tray",
                        description: Text("Start a recording to create your first session")
                    )
                } else if filteredSessions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                DateFilterBar(selection: $dateFilter)
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
                                Button {
                                    let sorted = session.segments.sorted { $0.startTime < $1.startTime }
                                    TranscriptExporter.copyToClipboard(segments: sorted, title: session.title)
                                } label: {
                                    Label("Copy Transcript", systemImage: "doc.on.doc")
                                }
                                .disabled(session.segments.isEmpty)
                                Divider()
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
        let skipTrash = UserDefaults.standard.bool(forKey: "skipTrashOnDelete")
        let label = ids.count == 1
            ? (skipTrash ? "Delete Permanently" : "Move to Trash")
            : (skipTrash ? "Delete \(ids.count) Permanently" : "Move \(ids.count) to Trash")
        return Button(label, role: .destructive) {
            sessionsToDelete = ids
            showDeleteConfirmation = true
        }
    }

    private func deleteSessions(ids: Set<UUID>) {
        let count = ids.count
        let skipTrash = UserDefaults.standard.bool(forKey: "skipTrashOnDelete")
        for id in ids {
            if let session = activeSessions.first(where: { $0.id == id }) {
                if skipTrash {
                    TrashCleanupService.permanentlyDelete(session: session, context: modelContext)
                } else {
                    session.moveToTrash()
                }
            }
        }
        do {
            try modelContext.save()
            Self.logger.info("\(skipTrash ? "Permanently deleted" : "Moved to trash") \(count) session(s)")
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
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(session.title)
                    .font(DS.Typography.sectionHeader)
                    .lineLimit(1)
                if session.isPartial {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.orange)
                        .help("Incomplete — saved on quit")
                }
            }

            HStack(spacing: DS.Spacing.xs) {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)

                if session.totalDuration > 0 {
                    Text("\u{00b7}")
                        .foregroundStyle(.secondary)
                    Text(session.totalDuration.compactDuration)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if !session.segments.isEmpty {
                    Text("\u{00b7}")
                        .foregroundStyle(.secondary)
                    Text("\(session.segments.count) segments")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if !session.summaries.isEmpty {
                    Text("\u{00b7}")
                        .foregroundStyle(.secondary)
                    Image(systemName: "text.badge.checkmark")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .help("\(session.summaries.count) summary/summaries")
                }
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [session.title, session.startedAt.formatted(date: .omitted, time: .shortened)]
        if session.totalDuration > 0 {
            parts.append(session.totalDuration.compactDuration)
        }
        if !session.segments.isEmpty {
            parts.append("\(session.segments.count) segments")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Date Filter Bar

/// Compact inline filter bar — understated pill chips that sit flush below the search field.
private struct DateFilterBar: View {
    @Binding var selection: DateFilter

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(DateFilter.allCases, id: \.self) { filter in
                DateFilterChip(
                    label: filter.rawValue,
                    isSelected: selection == filter
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = filter
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
    }
}

private struct DateFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.quaternary)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
