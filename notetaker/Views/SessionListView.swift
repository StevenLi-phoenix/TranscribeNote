import SwiftUI
import SwiftData
import os

enum DateFilter: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
}

/// Testable, nonisolated helper that counts sessions matching a date filter.
nonisolated enum DateFilterCounter {

    struct SessionDate {
        let startedAt: Date
    }

    /// Count sessions matching a given date filter.
    static func count(
        for filter: DateFilter,
        in sessions: [SessionDate],
        now: Date = Date()
    ) -> Int {
        switch filter {
        case .all:
            return sessions.count
        case .today:
            let calendar = Calendar.current
            return sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }.count
        case .thisWeek:
            let calendar = Calendar.current
            return sessions.filter { calendar.isDate($0.startedAt, equalTo: now, toGranularity: .weekOfYear) }.count
        case .thisMonth:
            let calendar = Calendar.current
            return sessions.filter { calendar.isDate($0.startedAt, equalTo: now, toGranularity: .month) }.count
        }
    }
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
    @State private var pinnedSessions: [RecordingSession] = []

    /// Applies text search filter to sessions. Pinned sessions skip date filter but respect search.
    private func searchFiltered(_ sessions: [RecordingSession]) -> [RecordingSession] {
        guard !searchText.isEmpty else { return sessions }
        let query = searchText
        return sessions.filter { session in
            if session.title.localizedCaseInsensitiveContains(query) { return true }
            if session.segments.contains(where: { $0.text.localizedCaseInsensitiveContains(query) }) { return true }
            if session.summaries.contains(where: { $0.content.localizedCaseInsensitiveContains(query) }) { return true }
            return false
        }
    }

    /// All non-deleted sessions (excludes trash).
    private var activeSessions: [RecordingSession] {
        sessions.filter { $0.deletedAt == nil }
    }

    private var filteredSessions: [RecordingSession] {
        var result = activeSessions.filter { !$0.isPinned }

        // Date filter (only for unpinned sessions)
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
        return searchFiltered(result)
    }

    private func updateGroupedSessions() {
        // Pinned sessions: not affected by date filter, but affected by search; exclude deleted
        pinnedSessions = searchFiltered(activeSessions.filter { $0.isPinned })
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }

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
                } else if filteredSessions.isEmpty && pinnedSessions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                DateFilterBar(selection: $dateFilter, sessions: activeSessions)
            }
    }

    private var sessionList: some View {
        List(selection: $selectedSessionIDs) {
            if !pinnedSessions.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedSessions, id: \.id) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                            .contextMenu { sessionContextMenu(for: session) }
                    }
                }
            }
            ForEach(groupedSessions, id: \.date) { group in
                Section(group.date.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(group.sessions, id: \.id) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                            .contextMenu { sessionContextMenu(for: session) }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                bulkPinButton(for: ids)
                deleteButton(for: ids)
            }
        }
    }

    @ViewBuilder
    private func sessionContextMenu(for session: RecordingSession) -> some View {
        Button {
            session.togglePin()
            withAnimation { updateGroupedSessions() }
        } label: {
            Label(
                session.isPinned ? "Unpin" : "Pin",
                systemImage: session.isPinned ? "pin.slash" : "pin"
            )
        }
        .accessibilityLabel(session.isPinned ? "Unpin session" : "Pin session")
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

    private func bulkPinButton(for ids: Set<UUID>) -> some View {
        let selected = sessions.filter { ids.contains($0.id) }
        let allPinned = selected.allSatisfy(\.isPinned)
        return Button {
            for session in selected {
                if allPinned {
                    if session.isPinned { session.togglePin() }
                } else {
                    if !session.isPinned { session.togglePin() }
                }
            }
            withAnimation { updateGroupedSessions() }
        } label: {
            Label(
                allPinned ? "Unpin" : "Pin",
                systemImage: allPinned ? "pin.slash" : "pin"
            )
        }
    }

    private func deleteButton(for ids: Set<UUID>) -> some View {
        let label = ids.count == 1 ? "Delete" : "Delete \(ids.count) Sessions"
        return Button(label, role: .destructive) {
            sessionsToDelete = ids
            showDeleteConfirmation = true
        }
    }

    private func deleteSessions(ids: Set<UUID>) {
        let count = ids.count
        let skipTrash = UserDefaults.standard.bool(forKey: "skipTrashOnDelete")
        for id in ids {
            if let session = sessions.first(where: { $0.id == id }) {
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
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pinned")
                }
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
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(session.totalDuration.compactDuration)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if !session.segments.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(session.segments.count) segments")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if !session.summaries.isEmpty {
                    Text("·")
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
        var parts: [String] = []
        if session.isPinned { parts.append("Pinned") }
        parts.append(contentsOf: [session.title, session.startedAt.formatted(date: .omitted, time: .shortened)])
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
    let sessions: [RecordingSession]

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(DateFilter.allCases, id: \.self) { filter in
                let count = filter == .all ? nil : countFor(filter)
                DateFilterChip(
                    label: filter.rawValue,
                    isSelected: selection == filter,
                    count: count
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

    private func countFor(_ filter: DateFilter) -> Int {
        DateFilterCounter.count(
            for: filter,
            in: sessions.map { .init(startedAt: $0.startedAt) }
        )
    }
}

private struct DateFilterChip: View {
    let label: String
    let isSelected: Bool
    var count: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xxs) {
                Text(label)
                if let count, count > 0 {
                    Text("(\(count))")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
