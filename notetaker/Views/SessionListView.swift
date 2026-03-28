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
    @State private var selectedTags: Set<String> = []

    @State private var groupedSessions: [(date: Date, sessions: [RecordingSession])] = []

    private var filteredSessions: [RecordingSession] {
        var result = sessions

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

        // Tag filter (AND logic: session must have ALL selected tags)
        if !selectedTags.isEmpty {
            result = result.filter { session in
                selectedTags.isSubset(of: Set(session.tags))
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
            .onDeleteCommand { deleteSessions(ids: selectedSessionIDs) }
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
                        updateGroupedSessions()
                    }
                }
            }
            .onChange(of: dateFilter) { updateGroupedSessions() }
            .onChange(of: selectedTags) { withAnimation { updateGroupedSessions() } }
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
                } else if filteredSessions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    DateFilterBar(selection: $dateFilter)
                    if !selectedTags.isEmpty {
                        HStack(spacing: DS.Spacing.xxs) {
                            ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                                TagPillView(tag: tag, isSelected: true) {
                                    selectedTags.remove(tag)
                                }
                            }
                            Button("Clear") {
                                withAnimation { selectedTags.removeAll() }
                            }
                            .font(DS.Typography.caption2)
                            .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
    }

    private var sessionList: some View {
        List(selection: $selectedSessionIDs) {
            ForEach(groupedSessions, id: \.date) { group in
                Section(group.date.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(group.sessions, id: \.id) { session in
                        SessionRowView(
                            session: session,
                            selectedTags: selectedTags,
                            onTagTap: { tag in
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                        )
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
                for audioURL in session.audioFileURLs {
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
    var selectedTags: Set<String> = []
    var onTagTap: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(session.title)
                    .font(DS.Typography.sectionHeader)
                    .lineLimit(1)
                if session.isPartial {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
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

            }

            if !session.tags.isEmpty {
                TagRow(
                    tags: session.tags,
                    maxVisible: 2,
                    selectedTags: selectedTags,
                    onTagTap: onTagTap
                )
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
    }
}
