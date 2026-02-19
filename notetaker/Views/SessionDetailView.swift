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
    @State private var summaryProgress: String?
    @State private var scrollToTime: TimeInterval?

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
                            generateChunkedSummary()
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
                                Text(summaryProgress ?? "Preparing...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                let sortedSummaries = session.summaries.sorted { a, b in
                                    if a.isOverall != b.isOverall { return a.isOverall }
                                    return a.coveringFrom < b.coveringFrom
                                }
                                ForEach(sortedSummaries, id: \.id) { block in
                                    SummaryCardView(block: block) {
                                        scrollToTime = block.coveringFrom
                                    }
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
                    TranscriptView(segments: sortedSegments, partialText: "", scrollToTime: $scrollToTime)
                }
            }
            .onAppear {
                loadAudio(for: session)
                if autoGenerateSummary && !hasAutoTriggeredSummary && !sortedSegments.isEmpty {
                    hasAutoTriggeredSummary = true
                    generateOverallSummary()
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
                summaryProgress = nil
                scrollToTime = nil
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

    /// Load overall LLM config with fallback chain: overallLLMConfigJSON → liveLLMConfigJSON → llmConfigJSON (legacy).
    private static func loadOverallLLMConfig() -> LLMConfig {
        for key in ["overallLLMConfigJSON", "liveLLMConfigJSON", "llmConfigJSON"] {
            if let json = UserDefaults.standard.string(forKey: key), !json.isEmpty {
                return LLMConfig.fromUserDefaults(key: key)
            }
        }
        return .default
    }

    /// Auto-triggered after recording — synthesizes chunk summaries into an overall summary.
    private func generateOverallSummary() {
        guard !sortedSegments.isEmpty else { return }
        isGeneratingSummary = true
        summaryGenerationError = nil
        summaryProgress = "Generating overall summary..."
        let id = sessionID

        summaryTask = Task { @MainActor in
            do {
                let llmConfig = Self.loadOverallLLMConfig()
                let summarizerConfig = SummarizerConfig.fromUserDefaults()
                let engine = LLMEngineFactory.create(from: llmConfig)
                let service = SummarizerService(engine: engine)

                let predicate = #Predicate<RecordingSession> { $0.id == id }
                guard let freshSession = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first else {
                    Self.logger.error("Session \(id) not found for overall summary")
                    self.summaryGenerationError = "Session not found."
                    self.isGeneratingSummary = false
                    self.summaryProgress = nil
                    return
                }

                // Check for existing chunk summaries (non-overall, non-pinned, non-user-edited)
                let chunkSummaries = freshSession.summaries.filter { !$0.isOverall && !$0.isPinned && !$0.userEdited }

                if chunkSummaries.isEmpty {
                    Self.logger.info("No chunk summaries found, falling back to chunked generation")
                    self.isGeneratingSummary = false
                    self.summaryProgress = nil
                    generateChunkedSummary()
                    return
                }

                // Build input tuples from chunk summaries
                let chunkInputs = chunkSummaries
                    .sorted { $0.coveringFrom < $1.coveringFrom }
                    .map { (coveringFrom: $0.coveringFrom, coveringTo: $0.coveringTo, content: $0.content) }

                let content = try await service.summarizeOverall(
                    chunkSummaries: chunkInputs,
                    config: summarizerConfig,
                    llmConfig: llmConfig
                )

                guard !Task.isCancelled, !content.isEmpty else {
                    self.isGeneratingSummary = false
                    self.summaryProgress = nil
                    return
                }

                // Re-fetch session after await
                guard let currentSession = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first else {
                    Self.logger.error("Session \(id) no longer exists after overall summarization")
                    self.summaryGenerationError = "Session was deleted during summary generation."
                    self.isGeneratingSummary = false
                    self.summaryProgress = nil
                    return
                }

                // Delete old overall summaries (non-pinned, non-user-edited)
                for existing in currentSession.summaries where existing.isOverall && !existing.isPinned && !existing.userEdited {
                    modelContext.delete(existing)
                }

                let overallFrom = chunkInputs.first?.coveringFrom ?? 0
                let overallTo = chunkInputs.last?.coveringTo ?? 0
                let block = SummaryBlock(
                    coveringFrom: overallFrom,
                    coveringTo: overallTo,
                    content: content,
                    style: summarizerConfig.summaryStyle,
                    model: llmConfig.model,
                    isOverall: true
                )
                block.session = currentSession
                modelContext.insert(block)
                do {
                    try modelContext.save()
                } catch {
                    Self.logger.error("Failed to save overall summary: \(error.localizedDescription)")
                }
                fetchSession()
            } catch {
                Self.logger.error("Overall summary generation failed: \(error.localizedDescription)")
                self.summaryGenerationError = error.localizedDescription
            }
            self.isGeneratingSummary = false
            self.summaryProgress = nil
        }
    }

    /// Manual toolbar button — regenerates chunked summaries from transcript segments.
    private func generateChunkedSummary() {
        guard !sortedSegments.isEmpty else { return }
        isGeneratingSummary = true
        summaryGenerationError = nil
        summaryProgress = nil
        let id = sessionID
        let segments = sortedSegments

        summaryTask = Task { @MainActor in
            do {
                let llmConfig = Self.loadOverallLLMConfig()
                let summarizerConfig = SummarizerConfig.fromUserDefaults()
                let engine = LLMEngineFactory.create(from: llmConfig)
                let service = SummarizerService(engine: engine)

                // Delete non-pinned, non-user-edited, non-overall summaries before regenerating
                let predicate = #Predicate<RecordingSession> { $0.id == id }
                if let freshSession = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first {
                    for existing in freshSession.summaries where !existing.isOverall && !existing.isPinned && !existing.userEdited {
                        modelContext.delete(existing)
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        Self.logger.error("Failed to delete old chunk summaries: \(error.localizedDescription)")
                    }
                }

                // Chunked summarization — one SummaryBlock per time window
                for try await progress in service.summarizeInChunks(
                    segments: segments,
                    intervalMinutes: summarizerConfig.intervalMinutes,
                    config: summarizerConfig,
                    llmConfig: llmConfig
                ) {
                    guard !Task.isCancelled else { break }

                    summaryProgress = "Generating chunk \(progress.chunkIndex + 1) of \(progress.totalChunks)..."

                    // Re-fetch session after each async suspension point
                    guard let currentSession = try? modelContext.fetch(
                        FetchDescriptor(predicate: predicate)
                    ).first else {
                        Self.logger.error("Session \(id) no longer exists; aborting summary generation")
                        summaryGenerationError = "Session was deleted during summary generation."
                        break
                    }

                    let block = SummaryBlock(
                        coveringFrom: progress.coveringFrom,
                        coveringTo: progress.coveringTo,
                        content: progress.content,
                        style: summarizerConfig.summaryStyle,
                        model: llmConfig.model
                    )
                    block.session = currentSession
                    modelContext.insert(block)
                    do {
                        try modelContext.save()
                    } catch {
                        Self.logger.error("Failed to save chunk \(progress.chunkIndex + 1): \(error.localizedDescription)")
                    }
                    fetchSession()
                }
            } catch {
                Self.logger.error("Chunked summary generation failed: \(error.localizedDescription)")
                self.summaryGenerationError = error.localizedDescription
            }
            self.isGeneratingSummary = false
            self.summaryProgress = nil
        }
    }

}
