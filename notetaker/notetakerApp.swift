import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: RecordingViewModel?
    var modelContainer: ModelContainer?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stopRecording(modelContext: modelContainer?.mainContext)
    }
}

@main
struct notetakerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = RecordingViewModel()

    private let sharedModelContainer: ModelContainer? = {
        let schema = Schema([RecordingSession.self, TranscriptSegment.self])
        let configuration = ModelConfiguration()
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            return nil
        }
    }()

    var body: some Scene {
        // Wire AppDelegate refs eagerly so applicationWillTerminate works
        // even if the main window never appeared (e.g. MenuBarExtra-only usage).
        let _ = {
            appDelegate.viewModel = viewModel
            appDelegate.modelContainer = sharedModelContainer
        }()

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
                    Text("The app's data store could not be created. Try relaunching the app.")
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
            Text(viewModel.formattedElapsedTime)
                .font(.system(.caption, design: .monospaced))
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
                    await viewModel.startRecording()
                }
            }
        }

        Divider()

        Button("Open Main Window") {
            openWindow(id: "main")
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
