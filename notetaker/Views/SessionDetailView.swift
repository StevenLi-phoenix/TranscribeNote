import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

struct SessionDetailView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SessionDetailView")

    let sessionID: UUID
    var autoGenerateSummary: Bool = false
    @Environment(\.modelContext) private var modelContext
    @State private var playbackService = AudioPlaybackService()
    @State private var session: RecordingSession?
    @State private var sortedSegments: [TranscriptSegment] = []
    @State private var isLoading = true
    @State private var fetchError: String?
    @State private var isGeneratingSummary = false
    @State private var summaryGenerationError: String?
    @State private var hasAutoTriggeredSummary = false
    @State private var summaryTask: Task<Void, Never>?

    var body: some View {
        if isLoading {
            ProgressView()
                .onAppear { fetchSession() }
        } else if let session {
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
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            TranscriptExporter.copyToClipboard(
                                segments: sortedSegments,
                                title: session.title
                            )
                        } label: {
                            Label("Copy Transcript", systemImage: "doc.on.doc")
                        }
                        .disabled(sortedSegments.isEmpty)

                        ShareLink(
                            item: TranscriptExporter.formatAsText(
                                segments: sortedSegments,
                                title: session.title
                            )
                        ) {
                            Label("Share Transcript", systemImage: "square.and.arrow.up")
                        }
                        .disabled(sortedSegments.isEmpty)

                        Button {
                            generateOnDemandSummary()
                        } label: {
                            if isGeneratingSummary {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Generate Summary", systemImage: "text.badge.star")
                            }
                        }
                        .disabled(sortedSegments.isEmpty || isGeneratingSummary)

                        if let audioURL = session.audioFileURL,
                           FileManager.default.fileExists(atPath: audioURL.path) {
                            Button {
                                let panel = NSSavePanel()
                                panel.allowedContentTypes = [audioURL.pathExtension == "m4a" ? .mpeg4Audio : .wav]
                                panel.nameFieldStringValue = audioURL.lastPathComponent
                                if panel.runModal() == .OK, let destURL = panel.url {
                                    do {
                                        try FileManager.default.copyItem(at: audioURL, to: destURL)
                                    } catch {
                                        Self.logger.error("Failed to save audio: \(error.localizedDescription)")
                                        fetchError = "Failed to save audio: \(error.localizedDescription)"
                                    }
                                }
                            } label: {
                                Label("Save Audio", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                }

                // Playback controls
                if session.audioFileURL != nil {
                    Divider()
                    PlaybackControlView(service: playbackService)
                }

                // Summaries section
                if isGeneratingSummary || !session.summaries.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summaries")
                            .font(.headline)
                            .padding(.horizontal)

                        if isGeneratingSummary {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.linear)
                                Text("Generating summary...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                let sortedSummaries = session.summaries.sorted { $0.coveringFrom < $1.coveringFrom }
                                ForEach(sortedSummaries, id: \.id) { block in
                                    SummaryCardView(block: block)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                    .padding(.vertical, 8)
                }

                if let summaryGenerationError {
                    Text(summaryGenerationError)
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .padding(.horizontal)
                }

                Divider()

                // Transcript
                if sortedSegments.isEmpty {
                    ContentUnavailableView(
                        "No Transcript",
                        systemImage: "text.bubble",
                        description: Text("This session has no transcript segments")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    TranscriptView(segments: sortedSegments, partialText: "")
                }
            }
            .onAppear {
                loadAudio(for: session)
                if autoGenerateSummary && !hasAutoTriggeredSummary && !sortedSegments.isEmpty {
                    hasAutoTriggeredSummary = true
                    generateOnDemandSummary()
                }
            }
            .onChange(of: sessionID) { _, _ in
                playbackService.stop()
                summaryTask?.cancel()
                sortedSegments = []
                isLoading = true
                hasAutoTriggeredSummary = false
                isGeneratingSummary = false
                summaryGenerationError = nil
                fetchSession()
            }
            .onDisappear {
                playbackService.stop()
                summaryTask?.cancel()
            }
        } else if let fetchError {
            ContentUnavailableView(
                "Failed to Load Session",
                systemImage: "exclamationmark.triangle",
                description: Text(fetchError)
            )
        } else {
            ContentUnavailableView(
                "Session Not Found",
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private func fetchSession() {
        let id = sessionID
        let predicate = #Predicate<RecordingSession> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        do {
            session = try modelContext.fetch(descriptor).first
            fetchError = nil
            if let session {
                sortedSegments = session.segments.sorted { $0.startTime < $1.startTime }
                loadAudio(for: session)
            }
        } catch {
            Self.logger.error("Failed to fetch session \(id): \(error.localizedDescription)")
            session = nil
            fetchError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadAudio(for session: RecordingSession) {
        guard let url = session.audioFileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        playbackService.load(url: url)
    }

    private func generateOnDemandSummary() {
        guard let session, !sortedSegments.isEmpty else { return }
        isGeneratingSummary = true
        summaryGenerationError = nil
        let id = sessionID

        summaryTask = Task { @MainActor in
            do {
                let llmConfig = LLMConfig.fromUserDefaults()
                let summarizerConfig = SummarizerConfig.fromUserDefaults()
                let engine = LLMEngineFactory.create(from: llmConfig)
                let service = SummarizerService(engine: engine)

                let content = try await service.summarize(
                    segments: sortedSegments,
                    previousSummary: nil,
                    config: summarizerConfig,
                    llmConfig: llmConfig
                )

                guard !Task.isCancelled, !content.isEmpty else { return }

                // Re-fetch session to verify it still exists
                let predicate = #Predicate<RecordingSession> { $0.id == id }
                guard let freshSession = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first else {
                    return
                }
                let block = SummaryBlock(
                    coveringFrom: sortedSegments.first?.startTime ?? 0,
                    coveringTo: sortedSegments.last?.endTime ?? 0,
                    content: content,
                    style: summarizerConfig.summaryStyle,
                    model: llmConfig.model
                )
                block.session = freshSession
                modelContext.insert(block)
                try modelContext.save()
                fetchSession()
            } catch {
                Self.logger.error("On-demand summary failed: \(error.localizedDescription)")
                self.summaryGenerationError = error.localizedDescription
            }
            self.isGeneratingSummary = false
        }
    }

}
