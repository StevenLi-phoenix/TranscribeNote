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
    @State private var showTemplatePicker = false
    @AppStorage("showTemplatePickerOnRecord") private var showTemplatePickerOnRecord = true

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
                            if showTemplatePickerOnRecord {
                                showTemplatePicker = true
                            } else {
                                startRecordingWithDefaults()
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
                .sheet(isPresented: $showTemplatePicker) {
                    TemplatePickerView { template in
                        startRecordingWithTemplate(template)
                    }
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

    // MARK: - Template Recording

    private func startRecordingWithDefaults() {
        selectedSessionID = nil
        Task { @MainActor in
            await viewModel.startRecording(modelContext: modelContext)
        }
    }

    private func startRecordingWithTemplate(_ template: MeetingTemplate?) {
        selectedSessionID = nil
        if let template {
            applyTemplateOverrides(template)
            Self.logger.info("Starting recording with template: \(template.name)")
        } else {
            Self.logger.info("Starting recording without template (skipped)")
        }
        Task { @MainActor in
            await viewModel.startRecording(modelContext: modelContext)
        }
    }

    /// Applies template overrides to UserDefaults-based summarizer config before recording starts.
    /// The RecordingViewModel reads config from UserDefaults at init, so we update it in-place.
    private func applyTemplateOverrides(_ template: MeetingTemplate) {
        var config = SummarizerConfig.fromUserDefaults()
        var changed = false

        if let interval = template.summaryIntervalMinutes {
            config.intervalMinutes = interval
            changed = true
        }
        if let styleRaw = template.summaryStyle, let style = SummaryStyle(rawValue: styleRaw) {
            config.summaryStyle = style
            changed = true
        }
        if let language = template.language {
            config.summaryLanguage = language
            changed = true
        }

        if changed {
            if let data = try? JSONEncoder().encode(config),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "summarizerConfigJSON")
                Self.logger.info("Applied template overrides: interval=\(config.intervalMinutes), style=\(config.summaryStyle.rawValue), language=\(config.summaryLanguage)")
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
