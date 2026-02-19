import SwiftUI
import SwiftData
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: RecordingViewModel?
    var modelContainer: ModelContainer?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel, viewModel.isRecording else {
            return .terminateNow
        }

        // Stop recording and wait for drain + final summary before quitting
        viewModel.stopRecording(modelContext: modelContainer?.mainContext)

        Task { @MainActor in
            await viewModel.awaitDrainCompletion()
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }
}

@main
struct notetakerApp: App {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "App")

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel: RecordingViewModel

    private let sharedModelContainer: ModelContainer?
    private let containerError: String?

    init() {
        CrashLogService.install()

        let liveLLMJSON = UserDefaults.standard.string(forKey: "liveLLMConfigJSON")
        let llmConfig: LLMConfig
        if let liveLLMJSON, !liveLLMJSON.isEmpty {
            llmConfig = LLMConfig.fromUserDefaults(key: "liveLLMConfigJSON")
        } else {
            llmConfig = LLMConfig.fromUserDefaults(key: "llmConfigJSON")
        }
        let summarizerConfig = SummarizerConfig.fromUserDefaults()
        _viewModel = State(initialValue: RecordingViewModel(llmConfig: llmConfig, summarizerConfig: summarizerConfig))

        let schema = Schema([RecordingSession.self, TranscriptSegment.self, SummaryBlock.self])
        let configuration = ModelConfiguration()
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [configuration])
            containerError = nil
        } catch {
            Self.logger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            sharedModelContainer = nil
            containerError = error.localizedDescription
        }

        // Wire AppDelegate refs eagerly so applicationShouldTerminate works
        // even if the main window never appeared (e.g. MenuBarExtra-only usage).
        appDelegate.viewModel = viewModel
        appDelegate.modelContainer = sharedModelContainer
    }

    var body: some Scene {

        WindowGroup(id: "main") {
            if let sharedModelContainer {
                ContentView(viewModel: viewModel)
                    .modelContainer(sharedModelContainer)
            } else {
                VStack(spacing: 12) {
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
                MenuBarView(viewModel: viewModel, modelContainer: sharedModelContainer)
            } else {
                Text("Database unavailable")
            }
        } label: {
            Image(systemName: viewModel.isRecording ? "record.circle.fill" : "mic")
                .symbolRenderingMode(.multicolor)
        }

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarView: View {
    @Bindable var viewModel: RecordingViewModel
    @Environment(\.openWindow) private var openWindow
    let modelContainer: ModelContainer

    var body: some View {
        if viewModel.isRecording {
            Label("Recording...", systemImage: "record.circle.fill")
                .foregroundStyle(.red)
            Text(viewModel.clock.formatted)
                .font(.system(.caption, design: .monospaced))
            if let summary = viewModel.latestSummary {
                Text(summary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.caption)
            }
            Divider()
            Button("Stop Recording") {
                viewModel.stopRecording(modelContext: modelContainer.mainContext)
            }
        } else {
            Label("Idle", systemImage: "mic")
                .foregroundStyle(.secondary)
            Divider()
            Button("Start Recording") {
                Task {
                    await viewModel.startRecording(modelContext: modelContainer.mainContext)
                }
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
