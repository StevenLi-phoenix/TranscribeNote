import SwiftUI
import SwiftData
import os

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
        UserDefaults.standard.register(defaults: ["soundEffectsEnabled": true])

        CrashLogService.install()
        KeychainMigration.migrateIfNeeded()
        SchedulerService.install()

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
                ScheduledRecording.self, ActionItem.self,
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
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if viewModel.state == .paused {
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
                        .font(DS.Typography.sectionHeader)
                    Text(containerError ?? "The app's data store could not be created. Try relaunching the app.")
                        .font(DS.Typography.body)
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
                    .fill(DS.Colors.recording)
                    .frame(width: 7, height: 7)
                    .opacity(pulsing ? 0.35 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }
                    .onDisappear { pulsing = false }
                Text("Recording")
                    .fontWeight(.medium)
                Spacer()
                Text(viewModel.clock.formatted)
                    .font(DS.Typography.timer)
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
        } else if viewModel.state == .paused {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                Text("Paused")
                    .fontWeight(.medium)
                Spacer()
                Text(viewModel.clock.formatted)
                    .font(DS.Typography.timer)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .frame(minWidth: 280)

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
        } else {
            Label("Not Recording", systemImage: "mic.slash")
                .foregroundStyle(.secondary)
            if let next = schedulerViewModel.nextScheduled, let fireTime = next.nextFireTime {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
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
            }
            Divider()
            Button {
                Task {
                    await viewModel.startRecording(modelContext: modelContainer.mainContext)
                }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
            }
        }

        Divider()

        Button("Open Main Window") {
            openWindow(id: "main")
        }

        SettingsLink()

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
