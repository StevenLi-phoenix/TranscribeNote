import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: RecordingViewModel
    var schedulerViewModel: SchedulerViewModel
    @State private var selectedSessionID: UUID?
    @State private var showScheduleSheet = false

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
            SessionListView(selectedSessionID: $selectedSessionID)
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
                    }
                }
                .sheet(isPresented: $showScheduleSheet) {
                    ScheduleView(schedulerViewModel: schedulerViewModel)
                        .frame(minWidth: 480, minHeight: 400)
                }
        } detail: {
            if viewModel.isActive || viewModel.state == .stopping {
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
                    description: Text("Select a session from the sidebar or press ⌘N to start recording")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            handleCompletionIfNeeded()
        }
        .onChange(of: viewModel.state) { _, newState in
            if newState == .completed {
                handleCompletionIfNeeded()
            }
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
