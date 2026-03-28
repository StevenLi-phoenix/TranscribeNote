import SwiftUI
import SwiftData
import os

struct ContentView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ContentView")

    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: RecordingViewModel
    var schedulerViewModel: SchedulerViewModel
    @State private var selectedSessionID: UUID?
    @State private var showScheduleSheet = false
    @State private var showTrash = false
    @State private var trashCount: Int = 0

    /// Handle recording completion — works both on initial appear and state change.
    /// Background summary is already dispatched by the ViewModel's drainTask.
    private func handleCompletionIfNeeded() {
        guard viewModel.state == .completed else { return }
        if let session = viewModel.currentSession {
            selectedSessionID = session.id
        }
        viewModel.dismissCompletedRecording()
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SessionListView(selectedSessionID: $selectedSessionID)

                Divider()

                Button {
                    showTrash = true
                    selectedSessionID = nil
                } label: {
                    Label {
                        Text("Trash")
                        if trashCount > 0 {
                            Spacer()
                            Text("\(trashCount)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "trash")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xs)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showTrash ? .primary : .secondary)
                .accessibilityLabel("Trash, \(trashCount) items")
            }
            .navigationSplitViewColumnWidth(min: DS.Layout.sidebarMinWidth, ideal: DS.Layout.sidebarIdealWidth)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedSessionID = nil
                        Task {
                            await viewModel.startRecording(modelContext: modelContext)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.isActive || viewModel.state == .stopping)
                    .keyboardShortcut("n", modifiers: [.command])
                    .accessibilityLabel("New recording")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showScheduleSheet = true
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                    }
                    .accessibilityLabel("Scheduled recordings")
                    .help("View and manage scheduled recordings")
                }
            }
            .sheet(isPresented: $showScheduleSheet) {
                ScheduleView(schedulerViewModel: schedulerViewModel)
                    .frame(minWidth: 480, minHeight: 400)
            }
        } detail: {
            if showTrash {
                TrashView()
                    .onChange(of: showTrash) {
                        refreshTrashCount()
                    }
            } else if viewModel.isActive || viewModel.state == .stopping {
                LiveRecordingView(
                    viewModel: viewModel,
                    onStop: {
                        viewModel.stopRecording(modelContext: modelContext)
                    },
                    onPause: {
                        Task {
                            await viewModel.pauseRecording()
                        }
                    },
                    onResume: {
                        Task {
                            await viewModel.resumeRecording()
                        }
                    }
                )
            } else if let sessionID = selectedSessionID {
                SessionDetailView(sessionID: sessionID)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "mic.badge.plus",
                    description: Text("Select a session from the sidebar, or press \u{2318}N to start a new recording.\nUse the menu bar icon for quick access.")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            handleCompletionIfNeeded()
            TrashCleanupService.cleanupExpired(context: modelContext)
            refreshTrashCount()
        }
        .onChange(of: selectedSessionID) { _, newValue in
            if newValue != nil { showTrash = false }
        }
        .onChange(of: viewModel.state) { _, newState in
            if newState == .completed {
                handleCompletionIfNeeded()
            }
        }
    }

    // MARK: - Trash

    private func refreshTrashCount() {
        do {
            let descriptor = FetchDescriptor<RecordingSession>(
                predicate: #Predicate { $0.deletedAt != nil }
            )
            trashCount = try modelContext.fetchCount(descriptor)
        } catch {
            trashCount = 0
        }
    }
}

#Preview {
    ContentView(
        viewModel: RecordingViewModel(asrEngine: NoopASREngine()),
        schedulerViewModel: SchedulerViewModel()
    )
    .modelContainer(for: [RecordingSession.self, TranscriptSegment.self], inMemory: true)
}
