import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: RecordingViewModel
    @State private var selectedSessionID: UUID?

    var body: some View {
        NavigationSplitView {
            SessionListView(selectedSessionID: $selectedSessionID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
                .toolbar {
                    ToolbarItem {
                        Button {
                            selectedSessionID = nil
                            Task {
                                await viewModel.startRecording()
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(viewModel.isRecording)
                        .keyboardShortcut("n", modifiers: [.command])
                        .accessibilityLabel("New recording")
                    }
                }
        } detail: {
            if viewModel.isRecording || viewModel.state == .stopping {
                LiveRecordingView(viewModel: viewModel) {
                    viewModel.stopRecording(modelContext: modelContext)
                }
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
        .onChange(of: viewModel.state) { oldValue, newValue in
            if oldValue == .stopping && newValue == .idle {
                if let session = viewModel.currentSession {
                    selectedSessionID = session.id
                }
            }
        }
    }
}

#Preview {
    ContentView(viewModel: RecordingViewModel(asrEngine: NoopASREngine()))
        .modelContainer(for: [RecordingSession.self, TranscriptSegment.self], inMemory: true)
}
