import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let sessionID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var playbackService = AudioPlaybackService()
    @State private var session: RecordingSession?
    @State private var sortedSegments: [TranscriptSegment] = []

    var body: some View {
        if let session {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        if session.totalDuration > 0 {
                            Text("·")
                            Text(session.totalDuration.compactDuration)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                // Playback controls
                if session.audioFilePath != nil {
                    Divider()
                    PlaybackControlView(service: playbackService)
                }

                Divider()

                // Transcript
                if sortedSegments.isEmpty {
                    ContentUnavailableView(
                        "No Transcript",
                        systemImage: "text.bubble",
                        description: Text("This session has no transcript segments")
                    )
                } else {
                    TranscriptView(segments: sortedSegments, partialText: "")
                }
            }
            .onAppear {
                sortedSegments = session.segments.sorted { $0.startTime < $1.startTime }
                loadAudio(for: session)
            }
            .onChange(of: sessionID) { _, _ in
                playbackService.stop()
                sortedSegments = []
                fetchSession()
            }
            .onDisappear { playbackService.stop() }
        } else {
            ContentUnavailableView(
                "Session Not Found",
                systemImage: "exclamationmark.triangle"
            )
            .onAppear { fetchSession() }
        }
    }

    private func fetchSession() {
        let id = sessionID
        let predicate = #Predicate<RecordingSession> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        session = try? modelContext.fetch(descriptor).first
        if let session {
            sortedSegments = session.segments.sorted { $0.startTime < $1.startTime }
            loadAudio(for: session)
        }
    }

    private func loadAudio(for session: RecordingSession) {
        guard let path = session.audioFilePath else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        playbackService.load(url: URL(fileURLWithPath: path))
    }
}
