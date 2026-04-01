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
    @State private var showCommandPalette = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasShownPrivacyDisclosure") private var hasShownPrivacyDisclosure = false
    @State private var showWelcome = false
    @State private var showPrivacyDisclosure = false

    /// Handle recording completion — works both on initial appear and state change.
    /// Background summary is already dispatched by the ViewModel's drainTask.
    private func handleCompletionIfNeeded() {
        guard viewModel.state == .completed else { return }
        // Only auto-navigate if user hasn't selected another session during drain
        if selectedSessionID == nil, let session = viewModel.currentSession {
            selectedSessionID = session.id
        }
        viewModel.dismissCompletedRecording()
    }

    var body: some View {
        NavigationSplitView {
            SessionListView(selectedSessionID: $selectedSessionID)
                .navigationSplitViewColumnWidth(min: DS.Layout.sidebarMinWidth, ideal: DS.Layout.sidebarIdealWidth, max: DS.Layout.sidebarMaxWidth)
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
        .frame(minWidth: 400, minHeight: 300)
        .alert("Recording Error", isPresented: Binding(
            get: { viewModel.criticalError != nil },
            set: { if !$0 { viewModel.criticalError = nil } }
        )) {
            Button("OK") { viewModel.criticalError = nil }
        } message: {
            Text(viewModel.criticalError ?? "")
        }
        .onAppear {
            handleCompletionIfNeeded()
            if !hasCompletedOnboarding {
                showWelcome = true
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView {
                hasCompletedOnboarding = true
                showWelcome = false
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            if newState == .completed {
                handleCompletionIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcomeGuide)) { _ in
            showWelcome = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPrivacyDisclosure)) { _ in
            showPrivacyDisclosure = true
        }
        .sheet(isPresented: $showPrivacyDisclosure) {
            PrivacyDisclosureView(onDismiss: {
                showPrivacyDisclosure = false
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                showCommandPalette.toggle()
            }
        }
        .overlay {
            if showCommandPalette {
                CommandPaletteView(
                    commands: buildPaletteCommands(),
                    isPresented: $showCommandPalette
                )
            }
        }
    }

    // MARK: - Command Palette

    private func buildPaletteCommands() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []

        // Recording
        if viewModel.isActive {
            commands.append(PaletteCommand(
                id: "stop-recording",
                title: "Stop Recording",
                subtitle: "End the current recording session",
                icon: "stop.fill",
                shortcut: nil,
                category: .recording,
                action: { [viewModel, modelContext] in
                    viewModel.stopRecording(modelContext: modelContext)
                }
            ))
        } else {
            commands.append(PaletteCommand(
                id: "start-recording",
                title: "Start Recording",
                subtitle: "Begin a new recording session",
                icon: "record.circle",
                shortcut: "⌘N",
                category: .recording,
                action: { [viewModel, modelContext] in
                    Task {
                        await viewModel.startRecording(modelContext: modelContext)
                    }
                }
            ))
        }

        if viewModel.isRecording {
            commands.append(PaletteCommand(
                id: "pause-recording",
                title: "Pause Recording",
                subtitle: nil,
                icon: "pause.fill",
                shortcut: nil,
                category: .recording,
                action: { [viewModel] in
                    Task { await viewModel.pauseRecording() }
                }
            ))
        } else if viewModel.state == .paused {
            commands.append(PaletteCommand(
                id: "resume-recording",
                title: "Resume Recording",
                subtitle: nil,
                icon: "play.fill",
                shortcut: nil,
                category: .recording,
                action: { [viewModel] in
                    Task { await viewModel.resumeRecording() }
                }
            ))
        }

        // Navigation
        commands.append(PaletteCommand(
            id: "open-settings",
            title: "Open Settings",
            subtitle: nil,
            icon: "gear",
            shortcut: "⌘,",
            category: .navigation,
            action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        ))

        commands.append(PaletteCommand(
            id: "command-palette",
            title: "Command Palette",
            subtitle: "Open this command palette",
            icon: "command",
            shortcut: "⌘K",
            category: .navigation,
            action: {} // Already open
        ))

        commands.append(PaletteCommand(
            id: "scheduled-recordings",
            title: "Scheduled Recordings",
            subtitle: "View and manage scheduled recordings",
            icon: "calendar.badge.plus",
            shortcut: nil,
            category: .navigation,
            action: { showScheduleSheet = true }
        ))

        // Playback
        commands.append(PaletteCommand(
            id: "toggle-playback",
            title: "Play / Pause",
            subtitle: "Toggle audio playback",
            icon: "play.pause.fill",
            shortcut: "Space",
            category: .playback,
            action: {
                NotificationCenter.default.post(name: .togglePlayback, object: nil)
            }
        ))

        commands.append(PaletteCommand(
            id: "seek-forward",
            title: "Skip Forward 5s",
            subtitle: nil,
            icon: "goforward.5",
            shortcut: "→",
            category: .playback,
            action: {
                NotificationCenter.default.post(name: .seekForward, object: nil)
            }
        ))

        commands.append(PaletteCommand(
            id: "seek-backward",
            title: "Skip Back 5s",
            subtitle: nil,
            icon: "gobackward.5",
            shortcut: "←",
            category: .playback,
            action: {
                NotificationCenter.default.post(name: .seekBackward, object: nil)
            }
        ))

        commands.append(PaletteCommand(
            id: "seek-forward-long",
            title: "Skip Forward 15s",
            subtitle: nil,
            icon: "goforward.15",
            shortcut: "⇧→",
            category: .playback,
            action: {
                NotificationCenter.default.post(name: .seekForwardLong, object: nil)
            }
        ))

        commands.append(PaletteCommand(
            id: "seek-backward-long",
            title: "Skip Back 15s",
            subtitle: nil,
            icon: "gobackward.15",
            shortcut: "⇧←",
            category: .playback,
            action: {
                NotificationCenter.default.post(name: .seekBackwardLong, object: nil)
            }
        ))

        // Export
        commands.append(PaletteCommand(
            id: "export-markdown",
            title: "Export Markdown",
            subtitle: "Export session as Markdown file",
            icon: "doc.text",
            shortcut: "⌘E",
            category: .export,
            action: {
                // Delegate to SessionDetailView's existing ⌘E handler via menu
                NSApp.sendAction(#selector(NSResponder.performKeyEquivalent(with:)), to: nil, from: nil)
            }
        ))

        return commands
    }
}

#Preview {
    ContentView(
        viewModel: RecordingViewModel(asrEngine: NoopASREngine()),
        schedulerViewModel: SchedulerViewModel()
    )
    .modelContainer(for: [RecordingSession.self, TranscriptSegment.self], inMemory: true)
}
