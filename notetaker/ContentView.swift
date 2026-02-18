import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: RecordingViewModel
    @State private var selectedSessionID: UUID?
    @State private var autoSummarySessionID: UUID?

    var body: some View {
        NavigationSplitView {
            SessionListView(selectedSessionID: $selectedSessionID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                .toolbar {
                    ToolbarItem {
                        Button {
                            selectedSessionID = nil
                            Task {
                                await viewModel.startRecording(modelContext: modelContext)
                            }
                        } label: {
                            Image(systemName: "record.circle")
                                .foregroundStyle(.red)
                        }
                        .disabled(viewModel.isRecording || viewModel.state == .stopping)
                        .keyboardShortcut("n", modifiers: [.command])
                        .accessibilityLabel("New recording")
                    }
                }
        } detail: {
            if viewModel.isRecording || viewModel.state == .stopping {
                LiveRecordingView(
                    viewModel: viewModel,
                    onStop: {
                        viewModel.stopRecording(modelContext: modelContext)
                    }
                )
            } else if let sessionID = selectedSessionID {
                SessionDetailView(sessionID: sessionID, autoGenerateSummary: sessionID == autoSummarySessionID)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "mic.badge.plus",
                    description: Text("Select a session from the sidebar or press ⌘N to start recording")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onChange(of: viewModel.state) { _, newState in
            if newState == .completed {
                // drainTask already called persistSession — just navigate and dismiss
                if let session = viewModel.currentSession {
                    selectedSessionID = session.id
                    autoSummarySessionID = session.id
                }
                viewModel.dismissCompletedRecording()
            }
        }
    }
}

#Preview {
    ContentView(viewModel: RecordingViewModel(asrEngine: NoopASREngine()))
        .modelContainer(for: [RecordingSession.self, TranscriptSegment.self], inMemory: true)
}
