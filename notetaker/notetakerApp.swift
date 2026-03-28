import SwiftUI
import SwiftData
import os

// MARK: - Playback Notification Names

extension Notification.Name {
    static let togglePlayback = Notification.Name("notetaker.togglePlayback")
    static let seekForward = Notification.Name("notetaker.seekForward")
    static let seekBackward = Notification.Name("notetaker.seekBackward")
    static let seekForwardLong = Notification.Name("notetaker.seekForwardLong")
    static let seekBackwardLong = Notification.Name("notetaker.seekBackwardLong")
    static let toggleCommandPalette = Notification.Name("notetaker.toggleCommandPalette")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: RecordingViewModel?
    var schedulerViewModel: SchedulerViewModel?
    var modelContainer: ModelContainer?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hasRecording = viewModel?.isActive == true

        if hasRecording {
            // Force-persist immediately without waiting for ASR drain or in-flight summaries
            viewModel?.forceQuitPersist(modelContext: modelContainer?.mainContext)
        }

        // Cancel all background summaries — don't wait for LLM responses
        BackgroundSummaryService.shared.cancelAll()

        GlobalHotkeyService.shared.unregister()

        return .terminateNow
    }
}

@main
struct notetakerApp: App {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "App")

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel: RecordingViewModel
    @State private var schedulerViewModel: SchedulerViewModel

    private let sharedModelContainer: ModelContainer?
    private let containerError: String?

    init() {
        CrashLogService.install()
        KeychainMigration.migrateIfNeeded()
        SchedulerService.install()

        if UserDefaults.standard.object(forKey: "soundEffectsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "soundEffectsEnabled")
        }

        let llmConfig = LLMProfileStore.resolveConfig(for: .live)
        let summarizerConfig = SummarizerConfig.fromUserDefaults()
        let vadConfig = VADConfig.fromUserDefaults()
        let vm = RecordingViewModel(llmConfig: llmConfig, summarizerConfig: summarizerConfig, vadConfig: vadConfig)
        _viewModel = State(initialValue: vm)
        let schedulerVM = SchedulerViewModel()
        schedulerVM.recordingViewModel = vm
        _schedulerViewModel = State(initialValue: schedulerVM)

        let configuration = ModelConfiguration()
        do {
            sharedModelContainer = try ModelContainer(
                for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self,
                ScheduledRecording.self,
                migrationPlan: NotetakerMigrationPlan.self,
                configurations: configuration
            )
            containerError = nil
        } catch {
            Self.logger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            sharedModelContainer = nil
            containerError = error.localizedDescription
        }

        // Wire AppDelegate refs eagerly so applicationShouldTerminate works
        // even if the main window never appeared (e.g. MenuBarExtra-only usage).
        appDelegate.viewModel = vm
        appDelegate.schedulerViewModel = schedulerVM
        appDelegate.modelContainer = sharedModelContainer

        // 3c: Auto-start is now handled directly by SchedulerViewModel.handleFire()
        // via direct callback to RecordingViewModel (no notification relay needed).

        // Wire global hotkey
        let hotkeyVM = vm
        let hotkeyContainer = sharedModelContainer
        GlobalHotkeyService.shared.onToggleRecording = { [weak hotkeyVM, weak hotkeyContainer] in
            guard let vm = hotkeyVM else { return }
            switch vm.state {
            case .idle, .completed:
                Task { @MainActor in
                    await vm.startRecording(modelContext: hotkeyContainer?.mainContext)
                }
            case .recording, .paused:
                vm.stopRecording(modelContext: hotkeyContainer?.mainContext)
            case .stopping:
                break // Ignore while stopping
            }
        }

        // Set hotkey defaults if first launch
        if UserDefaults.standard.object(forKey: "globalHotkeyEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "globalHotkeyEnabled")
        }
        if UserDefaults.standard.integer(forKey: "globalHotkeyKeyCode") == 0 {
            UserDefaults.standard.set(Int(GlobalHotkeyService.defaultKeyCode), forKey: "globalHotkeyKeyCode")
            UserDefaults.standard.set(Int(GlobalHotkeyService.defaultModifiers), forKey: "globalHotkeyModifiers")
        }

        GlobalHotkeyService.shared.register()
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if viewModel.state == .stopping {
            Image(systemName: "ellipsis.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else if viewModel.state == .paused {
            Image(systemName: "pause.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else if viewModel.isRecording {
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else if schedulerViewModel.nextScheduled != nil {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "mic")
                Image(systemName: "clock.fill")
                    .font(.system(size: 7, weight: .bold))
                    .offset(x: 3, y: 3)
            }
        } else {
            Image(systemName: "mic")
        }
    }

    var body: some Scene {

        WindowGroup(id: "main") {
            if let sharedModelContainer {
                ContentView(viewModel: viewModel, schedulerViewModel: schedulerViewModel)
                    .modelContainer(sharedModelContainer)
                    .onAppear {
                        schedulerViewModel.load(context: sharedModelContainer.mainContext)
                    }
            } else {
                VStack(spacing: DS.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("Failed to initialize database")
                        .font(.headline)
                    Text(containerError ?? "The app's data store could not be created. Try relaunching the app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        MenuBarExtra {
            if let sharedModelContainer {
                MenuBarView(viewModel: viewModel, schedulerViewModel: schedulerViewModel, modelContainer: sharedModelContainer)
            } else {
                Text("Database unavailable")
            }
        } label: {
            menuBarIcon
        }

        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("Privacy Policy") {
                    NSWorkspace.shared.open(PrivacyDisclosureView.privacyPolicyURL)
                }

                Button("Data Usage Information") {
                    // Reset disclosure flag so the sheet re-appears on next Settings open
                    UserDefaults.standard.set(false, forKey: "hasShownPrivacyDisclosure")
                }
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    NotificationCenter.default.post(name: .togglePlayback, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Skip Forward 5s") {
                    NotificationCenter.default.post(name: .seekForward, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("Skip Back 5s") {
                    NotificationCenter.default.post(name: .seekBackward, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Skip Forward 15s") {
                    NotificationCenter.default.post(name: .seekForwardLong, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .shift)

                Button("Skip Back 15s") {
                    NotificationCenter.default.post(name: .seekBackwardLong, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            }

            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }
}

struct MenuBarView: View {
    @Bindable var viewModel: RecordingViewModel
    var schedulerViewModel: SchedulerViewModel
    @Environment(\.openWindow) private var openWindow
    let modelContainer: ModelContainer
    @State private var pulsing = false

    var body: some View {
        if viewModel.isRecording {
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .opacity(pulsing ? 0.35 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }
                    .onDisappear { pulsing = false }
                Text("Recording")
                    .fontWeight(.medium)
                Spacer()
                Text(viewModel.clock.formatted)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.top, DS.Spacing.xs)
            .frame(minWidth: 280)

            AudioLevelBar(level: viewModel.audioMeter.level)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xs)
                .frame(minWidth: 280)

            if let summary = viewModel.latestSummary {
                Divider()
                Text(summary)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .frame(minWidth: 280, alignment: .leading)
            }

            Divider()

            Button {
                Task { await viewModel.pauseRecording() }
            } label: {
                Label("Pause Recording", systemImage: "pause.fill")
            }

            Button(role: .destructive) {
                viewModel.stopRecording(modelContext: modelContainer.mainContext)
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
            }
            .keyboardShortcut(".", modifiers: [.command])
        } else if viewModel.state == .paused {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                Text("Paused")
                    .fontWeight(.medium)
                Spacer()
                Text(viewModel.clock.formatted)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .frame(minWidth: 280)

            if let summary = viewModel.latestSummary {
                Divider()
                Text(summary)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .frame(minWidth: 280, alignment: .leading)
            }

            Divider()

            Button {
                Task { await viewModel.resumeRecording() }
            } label: {
                Label("Resume Recording", systemImage: "play.fill")
            }

            Button(role: .destructive) {
                viewModel.stopRecording(modelContext: modelContainer.mainContext)
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
            }
            .keyboardShortcut(".", modifiers: [.command])
        } else if viewModel.state == .stopping {
            HStack(spacing: DS.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .fontWeight(.medium)
                Spacer()
                Text(viewModel.clock.formatted)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .frame(minWidth: 280)
        } else {
            Label("Not Recording", systemImage: "mic.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Microphone idle, not recording")
            if let next = schedulerViewModel.nextScheduled, let fireTime = next.nextFireTime {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(next.title.isEmpty ? "Scheduled" : next.title)
                            .font(DS.Typography.caption)
                            .fontWeight(.medium)
                        Text(fireTime, style: .relative)
                            .font(DS.Typography.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .frame(minWidth: 200, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next scheduled recording: \(next.title.isEmpty ? "Untitled" : next.title)")
            }
            Divider()
            Button {
                Task {
                    await viewModel.startRecording(modelContext: modelContainer.mainContext)
                }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        Divider()

        Button("Open Main Window") {
            openWindow(id: "main")
        }
        .keyboardShortcut("o", modifiers: [.command])

        SettingsLink()

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
