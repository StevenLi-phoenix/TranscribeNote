import SwiftUI
import SwiftData
import EventKit

/// Shows all scheduled recordings grouped by label, with import-from-calendar support.
///
/// Editor is presented via `navigationDestination` (not a nested sheet) to avoid
/// macOS SwiftUI nested-sheet bugs where the inner sheet stops presenting after the first dismiss.
struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var schedulerViewModel: SchedulerViewModel

    @State private var editorItem: ScheduleEditorItem? = nil
    @State private var showCalendarImport = false

    var body: some View {
        NavigationStack {
            Group {
                if schedulerViewModel.scheduledRecordings.isEmpty {
                    emptyState
                } else {
                    recordingList
                }
            }
            .navigationTitle("Scheduled Recordings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showCalendarImport = true
                    } label: {
                        Label("Import from Calendar", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        editorItem = ScheduleEditorItem(recording: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(item: $editorItem) { item in
                ScheduleEditorView(
                    schedulerViewModel: schedulerViewModel,
                    existing: item.recording
                )
            }
            .sheet(isPresented: $showCalendarImport) {
                CalendarImportView(schedulerViewModel: schedulerViewModel)
            }
            // 4b: Refresh after import sheet dismisses
            .onChange(of: showCalendarImport) { _, isPresented in
                if !isPresented {
                    schedulerViewModel.load(context: modelContext)
                }
            }
            .onAppear {
                schedulerViewModel.load(context: modelContext)
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Scheduled Recordings", systemImage: "calendar.badge.plus")
        } description: {
            Text("Create a timed recording or import meetings from your calendar.")
        } actions: {
            Button("Add Schedule") {
                editorItem = ScheduleEditorItem(recording: nil)
            }
            .buttonStyle(.borderedProminent)
            Button("Import from Calendar") {
                showCalendarImport = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var recordingList: some View {
        List {
            ForEach(schedulerViewModel.recordingsByLabel, id: \.label) { group in
                Section(group.label) {
                    ForEach(group.recordings) { recording in
                        ScheduledRecordingRow(
                            recording: recording,
                            schedulerViewModel: schedulerViewModel,
                            onEdit: {
                                editorItem = ScheduleEditorItem(recording: recording)
                            },
                            onDelete: {
                                schedulerViewModel.delete(recording, context: modelContext)
                            }
                        )
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let r = group.recordings[index]
                            schedulerViewModel.delete(r, context: modelContext)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct ScheduledRecordingRow: View {
    let recording: ScheduledRecording
    var schedulerViewModel: SchedulerViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title.isEmpty ? "Untitled" : recording.title)
                    .fontWeight(.medium)
                HStack(spacing: DS.Spacing.xs) {
                    Text(recording.startTime, style: .date)
                    Text(recording.startTime, style: .time)
                    if recording.rule != .once {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(recording.rule.displayName)
                    }
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                if let next = recording.nextFireTime {
                    Text("Next: \(next, style: .relative)")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.tertiary)
                } else if recording.rule == .once {
                    Text("Passed")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { recording.isEnabled },
                set: { _ in schedulerViewModel.toggleEnabled(recording, context: modelContext) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Editor Item

/// Wrapper for `navigationDestination(item:)` — each instance gets a unique `id`, ensuring SwiftUI
/// always presents a fresh destination even when creating multiple new recordings in a row.
struct ScheduleEditorItem: Identifiable, Hashable {
    let id = UUID()
    let recording: ScheduledRecording?

    static func == (lhs: ScheduleEditorItem, rhs: ScheduleEditorItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Calendar Import Sheet

private struct CalendarImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var schedulerViewModel: SchedulerViewModel

    @State private var selectedIDs: Set<UUID> = []
    // 4a: Configurable import window
    @State private var importDays: Int = 7
    private let dayOptions = [1, 3, 7, 14, 30]

    var body: some View {
        NavigationStack {
            Group {
                if schedulerViewModel.isLoadingCalendar {
                    ProgressView("Loading calendar events…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = schedulerViewModel.calendarError {
                    ContentUnavailableView {
                        Label("Calendar Unavailable", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(error)
                    }
                } else if schedulerViewModel.calendarEvents.isEmpty {
                    ContentUnavailableView(
                        "No Upcoming Meetings",
                        systemImage: "calendar",
                        description: Text("No meetings found in the next \(importDays) day(s).")
                    )
                } else {
                    List(schedulerViewModel.calendarEvents, selection: $selectedIDs) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .fontWeight(.medium)
                            HStack(spacing: DS.Spacing.xs) {
                                Text(item.startDate, style: .date)
                                Text(item.startDate, style: .time)
                                if let endDate = item.endDate {
                                    Text("–")
                                        .foregroundStyle(.tertiary)
                                    Text(endDate, style: .time)
                                }
                                if !item.calendarName.isEmpty {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(item.calendarName).foregroundStyle(.secondary)
                                }
                            }
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)

                            // 4c: Show location and notes for context
                            if let location = item.location, !location.isEmpty {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "mappin")
                                    Text(location)
                                }
                                .font(DS.Typography.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            if let notes = item.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(DS.Typography.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import from Calendar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // 4a: Import range picker — separate ToolbarItem to avoid macOS sheet toolbar clipping
                ToolbarItem(placement: .primaryAction) {
                    Picker("Range", selection: $importDays) {
                        ForEach(dayOptions, id: \.self) { days in
                            Text(days == 1 ? "Today" : "\(days) days").tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import (\(selectedIDs.count))") {
                        let items = schedulerViewModel.calendarEvents.filter { selectedIDs.contains($0.id) }
                        schedulerViewModel.importCalendarEvents(items, context: modelContext)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .task(id: importDays) {
                // Re-fetch when import range changes (4a) or on initial appear
                await schedulerViewModel.importFromCalendar(context: modelContext, days: importDays)
            }
        }
        .frame(minWidth: 400, minHeight: 360)
    }
}
