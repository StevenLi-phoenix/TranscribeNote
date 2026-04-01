import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

struct SessionDetailView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SessionDetailView")

    let sessionID: UUID
    @Environment(\.modelContext) private var modelContext
    @State private var playbackService = AudioPlaybackService()
    @State private var session: RecordingSession?
    @State private var sortedSegments: [TranscriptSegment] = []
    @State private var isLoading = true
    @State private var fetchError: String?
    @State private var isGeneratingSummary = false
    @State private var summaryGenerationError: String?
    @State private var summaryTask: Task<Void, Never>?
    @State private var summaryProgress: String?
    @State private var scrollToTime: TimeInterval?
    @State private var lastScrolledSegmentID: UUID?
    @State private var activeChunkID: PersistentIdentifier?
    @State private var scrollToChunkID: PersistentIdentifier?
    @AppStorage("autoScrollDuringPlayback") private var autoScrollDuringPlayback = true
    @State private var refreshTimer: Timer?
    @State private var isExportingAudio = false
    @AppStorage("sessionDetailTab") private var selectedTab = 0
    @State private var showActionItemsPopover = false
    @State private var exportSuccessMessage: String?
    @State private var overallSummary: SummaryBlock?
    @State private var chunkSummaries: [SummaryBlock] = []
    @State private var sortedActionItems: [ActionItem] = []
    @State private var hasAudioFiles = false
    @AppStorage("chatPanelOpen") private var isChatOpen = false
    @AppStorage("chatPanelMode") private var chatPanelModeRaw = "inline"
    @AppStorage("chatPanelWidth") private var chatPanelWidth: Double = 320
    @State private var chatViewModel: ChatViewModel?
    @State private var chatWindowController: ChatWindowController?
    @State private var detailWidth: CGFloat = 1000

    var body: some View {
        if isLoading {
            ProgressView()
                .accessibilityLabel("Loading session")
                .onAppear { fetchSession() }
        } else if let session {
            HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(session.title)
                        .font(DS.Typography.title)

                    HStack {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        if session.totalDuration > 0 {
                            Text("·")
                            Text(session.totalDuration.compactDuration)
                        }
                        if session.isPartial {
                            Label("Incomplete — saved on quit", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Colors.subtleError)
                        }
                    }
                    .font(DS.Typography.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityElement(children: .combine)
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

                        if isGeneratingSummary {
                            ProgressView().controlSize(.small)
                        } else {
                            Menu {
                                Button {
                                    generateCompleteSummary()
                                } label: {
                                    Label("Complete Summary", systemImage: "text.badge.checkmark")
                                }
                                Button {
                                    generateChunkedSummary()
                                } label: {
                                    Label("Chunked Summary", systemImage: "text.badge.star")
                                }
                                Divider()
                                Button {
                                    extractActionItems()
                                } label: {
                                    Label("Extract Action Items", systemImage: "checklist")
                                }
                            } label: {
                                Label("Generate Summary", systemImage: "text.badge.star")
                            }
                            .disabled(sortedSegments.isEmpty)
                        }

                        if hasAudioFiles {
                            if isExportingAudio {
                                ProgressView()
                                    .controlSize(.small)
                                    .help("Exporting audio…")
                            } else {
                                Button {
                                    exportAudio(session: session)
                                } label: {
                                    Label("Save Audio", systemImage: "square.and.arrow.down")
                                }
                            }
                        }

                        if !sortedActionItems.isEmpty {
                            Button {
                                showActionItemsPopover.toggle()
                            } label: {
                                Label("Action Items (\(sortedActionItems.count))", systemImage: "checklist.checked")
                            }
                            .help("View extracted action items")
                            .popover(isPresented: $showActionItemsPopover, arrowEdge: .bottom) {
                                ActionItemListView(
                                    actionItems: sortedActionItems,
                                    sessionTitle: session.title,
                                    onExportReminders: { exportActionItemsToReminders() },
                                    onExportCalendar: { exportActionItemsToCalendar() }
                                )
                                .frame(width: 400, height: 350)
                            }
                        }

                        Menu {
                            Button {
                                switchChatMode(.inline)
                            } label: {
                                Label("Show in Main Window", systemImage: "sidebar.right")
                            }
                            .disabled(detailWidth < DS.Layout.narrowWindowThreshold && !isInlineChat)

                            Button {
                                switchChatMode(.window)
                            } label: {
                                Label("Open in Separate Window", systemImage: "macwindow")
                            }

                            Divider()

                            Button("Close Chat Panel") {
                                closeChat()
                            }
                            .disabled(!isChatOpen)
                        } label: {
                            Label("Chat", systemImage: isChatOpen ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                        } primaryAction: {
                            toggleChat()
                        }
                        .disabled(sortedSegments.isEmpty)
                        .help("Ask questions about this transcript")
                    }
                }

                // Playback controls
                if !session.audioFileURLs.isEmpty {
                    Divider()
                    PlaybackControlView(service: playbackService)
                }

                // Subtab picker: Summary / Transcript
                Divider()
                Picker(selection: $selectedTab) {
                    Text("Summary").tag(0)
                    Text("Transcript").tag(1)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, DS.Spacing.xs)
                .accessibilityLabel("Session view")
                .animation(.easeInOut(duration: 0.25), value: selectedTab)

                ZStack {
                    if selectedTab == 0 {
                        summaryTabContent
                            .transition(.move(edge: .leading))
                    } else {
                        transcriptTabContent
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: selectedTab)

            }
            .frame(minWidth: 50, maxWidth: .infinity)
            .layoutPriority(1)
            .overlay(alignment: .bottomTrailing) {
                if isInlineChat && detailWidth < DS.Layout.narrowWindowThreshold {
                    ChatNarrowHintView {
                        switchChatMode(.window)
                    }
                    .padding(DS.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if isInlineChat, let vm = chatViewModel {
                VerticalResizeHandle(width: $chatPanelWidth, minWidth: 250, maxWidth: 500)
                ChatViewContent(viewModel: vm)
                    .frame(width: chatPanelWidth)
            }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: DetailWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(DetailWidthKey.self) { newWidth in
                detailWidth = newWidth
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in
                guard playbackService.duration > 0 else { return }
                playbackService.togglePlayPause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .seekForward)) { _ in
                guard playbackService.duration > 0 else { return }
                playbackService.seek(to: playbackService.currentTime + 5)
            }
            .onReceive(NotificationCenter.default.publisher(for: .seekBackward)) { _ in
                guard playbackService.duration > 0 else { return }
                playbackService.seek(to: playbackService.currentTime - 5)
            }
            .onReceive(NotificationCenter.default.publisher(for: .seekForwardLong)) { _ in
                guard playbackService.duration > 0 else { return }
                playbackService.seek(to: playbackService.currentTime + 15)
            }
            .onReceive(NotificationCenter.default.publisher(for: .seekBackwardLong)) { _ in
                guard playbackService.duration > 0 else { return }
                playbackService.seek(to: playbackService.currentTime - 15)
            }
            .onChange(of: selectedTab) { _, newTab in
                guard autoScrollDuringPlayback, playbackService.isPlaying else { return }
                let time = playbackService.currentTime
                if newTab == 1 {
                    let seg = sortedSegments.last { $0.startTime <= time }
                    lastScrolledSegmentID = seg?.id
                    if let seg { scrollToTime = seg.startTime }
                } else if newTab == 0 {
                    let chunk = chunkSummaries.last { $0.coveringFrom <= time }
                    activeChunkID = chunk?.persistentModelID
                    scrollToChunkID = chunk?.persistentModelID
                }
            }
            .onChange(of: playbackService.currentTime) { _, newTime in
                guard autoScrollDuringPlayback, playbackService.isPlaying else { return }
                if selectedTab == 1 {
                    let currentSegment = sortedSegments.last { $0.startTime <= newTime }
                    guard let currentSegment, currentSegment.id != lastScrolledSegmentID else { return }
                    lastScrolledSegmentID = currentSegment.id
                    scrollToTime = currentSegment.startTime
                } else if selectedTab == 0 {
                    let currentChunk = chunkSummaries.last { $0.coveringFrom <= newTime }
                    let chunkPID = currentChunk?.persistentModelID
                    guard chunkPID != activeChunkID else { return }
                    activeChunkID = chunkPID
                    if let chunkPID {
                        scrollToChunkID = chunkPID
                    }
                }
            }
            .onAppear {
                loadAudio(for: session)
                startRefreshTimerIfNeeded()
            }
            .onChange(of: sessionID) { _, _ in
                playbackService.stop()
                summaryTask?.cancel()
                refreshTimer?.invalidate()
                refreshTimer = nil
                sortedSegments = []
                overallSummary = nil
                chunkSummaries = []
                sortedActionItems = []
                hasAudioFiles = false
                isLoading = true
                isGeneratingSummary = false
                summaryGenerationError = nil
                summaryProgress = nil
                scrollToTime = nil
                lastScrolledSegmentID = nil
                activeChunkID = nil
                scrollToChunkID = nil
                showActionItemsPopover = false
                exportSuccessMessage = nil
                fetchSession()
            }
            .onDisappear {
                playbackService.stop()
                summaryTask?.cancel()
                refreshTimer?.invalidate()
                refreshTimer = nil
                dismissChatWindow()
            }
            .alert("Error", isPresented: Binding(
                get: { summaryGenerationError != nil },
                set: { if !$0 { summaryGenerationError = nil } }
            )) {
                Button("OK") { summaryGenerationError = nil }
            } message: {
                Text(summaryGenerationError ?? "")
            }
            .alert("Success", isPresented: Binding(
                get: { exportSuccessMessage != nil },
                set: { if !$0 { exportSuccessMessage = nil } }
            )) {
                Button("OK") { exportSuccessMessage = nil }
            } message: {
                Text(exportSuccessMessage ?? "")
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

    // MARK: - Tab Content

    @ViewBuilder
    private var summaryTabContent: some View {
        if overallSummary == nil && chunkSummaries.isEmpty {
            ContentUnavailableView(
                "No Summaries",
                systemImage: "text.badge.star",
                description: Text("Generate a summary from the toolbar")
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
                        if let overall = overallSummary {
                            Text("Overall Summary")
                                .font(DS.Typography.sectionHeader)
                                .padding(.horizontal)
                            SummaryCardView(
                                block: overall,
                                onSave: { newContent in
                                    saveEditedSummary(block: overall, content: newContent)
                                },
                                onRegenerate: { instructions in
                                    regenerateSummary(block: overall, instructions: instructions)
                                }
                            )
                            .padding(.horizontal)
                        }

                        if !chunkSummaries.isEmpty {
                            Text("Chunk Summaries")
                                .font(DS.Typography.sectionHeader)
                                .padding(.horizontal)
                            ForEach(chunkSummaries.sorted(by: { $0.coveringFrom < $1.coveringFrom })) { chunk in
                                SummaryCardView(
                                    block: chunk,
                                    onSave: { newContent in
                                        saveEditedSummary(block: chunk, content: newContent)
                                    },
                                    onRegenerate: { instructions in
                                        regenerateSummary(block: chunk, instructions: instructions)
                                    }
                                )
                                .id(chunk.persistentModelID)
                                .opacity(!playbackService.isPlaying || activeChunkID == nil || chunk.persistentModelID == activeChunkID ? 1.0 : 0.35)
                                .animation(.easeInOut(duration: 0.2), value: activeChunkID)
                                .animation(.easeInOut(duration: 0.2), value: playbackService.isPlaying)
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, DS.Spacing.sm)
                }
                .onChange(of: scrollToChunkID) { _, chunkID in
                    guard let chunkID else { return }
                    withAnimation {
                        proxy.scrollTo(chunkID, anchor: .top)
                    }
                    scrollToChunkID = nil
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptTabContent: some View {
        if sortedSegments.isEmpty {
            ContentUnavailableView(
                "No Transcript",
                systemImage: "text.bubble",
                description: Text("This session has no transcript segments")
            )
            .frame(maxHeight: .infinity)
        } else {
            TranscriptView(
                segments: sortedSegments,
                partialText: "",
                summaries: [],
                scrollToTime: $scrollToTime,
                activeSegmentID: playbackService.isPlaying ? lastScrolledSegmentID : nil
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
                // Pre-compute summary classifications in one pass
                var overall: SummaryBlock?
                var chunks: [SummaryBlock] = []
                for summary in session.summaries {
                    if summary.isOverall {
                        overall = summary
                    } else {
                        chunks.append(summary)
                    }
                }
                overallSummary = overall
                chunkSummaries = chunks
                sortedActionItems = session.actionItems.sorted { $0.createdAt < $1.createdAt }
                hasAudioFiles = session.audioFileURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
                chatViewModel?.configure(sessionID: sessionID, segments: sortedSegments)
                chatWindowController?.updateTitle(session.title)
            }
        } catch {
            Self.logger.error("Failed to fetch session \(id): \(error.localizedDescription)")
            session = nil
            fetchError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadAudio(for session: RecordingSession) {
        let urls = session.audioFileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        playbackService.loadMultiple(urls: urls)
    }

    /// Load overall LLM config via profile store with inheritance and legacy fallback.
    private static func loadOverallLLMConfig() -> LLMConfig {
        LLMProfileStore.resolveConfig(for: .overall)
    }

    /// Poll for background summary completion and refresh the view when new summaries arrive.
    private func startRefreshTimerIfNeeded() {
        let bgService = BackgroundSummaryService.shared
        guard bgService.isRunning(for: sessionID) || bgService.isExtractingActionItems(for: sessionID) else { return }
        isGeneratingSummary = true
        summaryProgress = "Generating summary in background..."
        refreshTimer?.invalidate()
        let id = sessionID
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak refreshTimer] _ in
            let stillRunning = bgService.isRunning(for: id) || bgService.isExtractingActionItems(for: id)
            if !stillRunning {
                refreshTimer?.invalidate()
                self.refreshTimer = nil
                self.isGeneratingSummary = false
                self.summaryProgress = nil
            }
            self.fetchSession()
        }
        refreshTimer?.tolerance = 0.5
    }

    /// Manual toolbar button — generates a single complete summary of all transcript segments.
    private func generateCompleteSummary() {
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

                // Delete existing non-pinned, non-user-edited summaries before regenerating
                let predicate = #Predicate<RecordingSession> { $0.id == id }
                guard let freshSession = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first else {
                    summaryGenerationError = "Session was deleted."
                    isGeneratingSummary = false
                    return
                }
                for existing in freshSession.summaries where !existing.isPinned && !existing.userEdited {
                    modelContext.delete(existing)
                }
                modelContext.saveQuietly()

                summaryProgress = "Generating complete summary…"
                var content: String
                var structuredResult: StructuredSummary?
                switch summarizerConfig.overallSummaryMode {
                case .rawText:
                    let rawResult = try await service.summarizeWithFallback(
                        segments: segments,
                        previousSummary: nil,
                        config: summarizerConfig,
                        llmConfig: llmConfig
                    )
                    content = rawResult.content
                    structuredResult = rawResult.structured
                case .chunkSummaries, .auto:
                    let chunks = freshSession.summaries
                        .filter { !$0.isOverall && !$0.isPinned }
                        .sorted { $0.coveringFrom < $1.coveringFrom }
                    if !chunks.isEmpty && summarizerConfig.overallSummaryMode != .rawText {
                        Self.logger.info("Using \(chunks.count) chunk summaries for overall synthesis")
                        let chunkInputs = chunks.map { (coveringFrom: $0.coveringFrom, coveringTo: $0.coveringTo, content: $0.content) }
                        content = try await service.summarizeOverall(
                            chunkSummaries: chunkInputs,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                    } else {
                        if summarizerConfig.overallSummaryMode == .chunkSummaries {
                            Self.logger.warning("No chunk summaries available, falling back to raw text")
                        }
                        let fallbackResult = try await service.summarizeWithFallback(
                            segments: segments,
                            previousSummary: nil,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                        content = fallbackResult.content
                        structuredResult = fallbackResult.structured
                    }
                }
                guard !content.isEmpty else {
                    summaryGenerationError = "Summary was empty — transcript may be too short."
                    isGeneratingSummary = false
                    summaryProgress = nil
                    return
                }

                // Re-fetch after async suspension
                guard let currentSession = try? modelContext.fetch(
                    FetchDescriptor(predicate: predicate)
                ).first else {
                    summaryGenerationError = "Session was deleted during summary generation."
                    isGeneratingSummary = false
                    summaryProgress = nil
                    return
                }

                let coveringTo = segments.map(\.endTime).max() ?? 0
                let block = SummaryBlock(
                    coveringFrom: 0,
                    coveringTo: coveringTo,
                    content: content,
                    style: summarizerConfig.summaryStyle,
                    model: llmConfig.model,
                    isOverall: true,
                    structuredContent: structuredResult?.toJSON()
                )
                block.session = currentSession
                modelContext.insert(block)
                modelContext.saveQuietly()
                fetchSession()
            } catch {
                Self.logger.error("Complete summary generation failed: \(error.localizedDescription)")
                summaryGenerationError = error.localizedDescription
            }
            isGeneratingSummary = false
            summaryProgress = nil
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

    private func saveEditedSummary(block: SummaryBlock, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Self.logger.warning("Attempted to save empty edited content")
            return
        }
        block.editedContent = trimmed
        block.userEdited = true
        do {
            try modelContext.save()
            Self.logger.info("Saved edited summary for block \(block.id)")
        } catch {
            Self.logger.error("Failed to save edited summary: \(error.localizedDescription)")
            summaryGenerationError = "Failed to save edit: \(error.localizedDescription)"
        }
    }

    private func regenerateSummary(block: SummaryBlock, instructions: String) {
        let id = sessionID
        let blockCoveringFrom = block.coveringFrom
        let blockCoveringTo = block.coveringTo
        let blockID = block.id
        let capturedSegments = sortedSegments

        isGeneratingSummary = true
        summaryGenerationError = nil

        summaryTask = Task { @MainActor in
            do {
                let llmConfig = Self.loadOverallLLMConfig()
                let summarizerConfig = SummarizerConfig.fromUserDefaults()
                let engine = LLMEngineFactory.create(from: llmConfig)
                let service = SummarizerService(engine: engine)

                // Filter segments to the block's time range (use captured segments for prompt)
                let relevantSegments = capturedSegments.filter {
                    $0.startTime >= blockCoveringFrom && $0.startTime < blockCoveringTo
                }

                guard !relevantSegments.isEmpty else {
                    summaryGenerationError = "No transcript segments in this time range."
                    isGeneratingSummary = false
                    return
                }

                let content = try await service.summarizeWithInstructions(
                    segments: relevantSegments,
                    instructions: instructions,
                    config: summarizerConfig,
                    llmConfig: llmConfig
                )

                guard !Task.isCancelled, !content.isEmpty else {
                    isGeneratingSummary = false
                    return
                }

                // Re-fetch session after await — captured references may be stale
                let predicate = #Predicate<RecordingSession> { $0.id == id }
                guard let currentSession = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first else {
                    summaryGenerationError = "Session was deleted during regeneration."
                    isGeneratingSummary = false
                    return
                }

                if let targetBlock = currentSession.summaries.first(where: { $0.id == blockID }) {
                    targetBlock.content = content
                    targetBlock.generatedAt = Date()
                    targetBlock.editedContent = nil
                    targetBlock.userEdited = false
                    try modelContext.save()
                    fetchSession()
                }
            } catch {
                Self.logger.error("Guided regeneration failed: \(error.localizedDescription)")
                summaryGenerationError = error.localizedDescription
            }
            isGeneratingSummary = false
        }
    }

    // MARK: - Action Items

    private func extractActionItems() {
        guard let session else { return }
        let id = sessionID
        let capturedSegments = sortedSegments

        isGeneratingSummary = true
        summaryGenerationError = nil

        summaryTask = Task { @MainActor in
            do {
                let llmConfig = LLMProfileStore.resolveConfig(for: .actionItems)
                let summarizerConfig = SummarizerConfig.fromUserDefaults()
                let engine = LLMEngineFactory.create(from: llmConfig)
                let service = SummarizerService(engine: engine)

                let rawItems = try await service.extractActionItems(
                    segments: capturedSegments,
                    config: summarizerConfig,
                    llmConfig: llmConfig
                )

                guard !Task.isCancelled else {
                    isGeneratingSummary = false
                    return
                }

                // Re-fetch session after await
                let predicate = #Predicate<RecordingSession> { $0.id == id }
                guard let currentSession = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first else {
                    summaryGenerationError = "Session was deleted during extraction."
                    isGeneratingSummary = false
                    return
                }

                // Remove old action items
                for existing in currentSession.actionItems {
                    modelContext.delete(existing)
                }

                for raw in rawItems {
                    let item = ActionItem(
                        content: raw.content,
                        dueDate: ActionItemParser.parseDate(raw.dueDate),
                        assignee: raw.assignee,
                        category: ActionItemCategory(rawValue: raw.category) ?? .task
                    )
                    item.session = currentSession
                    modelContext.insert(item)
                }

                try modelContext.save()
                fetchSession()
                Self.logger.info("Extracted \(rawItems.count) action items manually")
                if rawItems.isEmpty {
                    exportSuccessMessage = "No action items found in this transcript."
                } else {
                    exportSuccessMessage = "Extracted \(rawItems.count) action items."
                }
            } catch {
                Self.logger.error("Action item extraction failed: \(error.localizedDescription)")
                summaryGenerationError = error.localizedDescription
            }
            isGeneratingSummary = false
        }
    }

    private func exportActionItemsToReminders() {
        guard let session else { return }
        let items = session.actionItems.filter { !$0.isCompleted }
        guard !items.isEmpty else {
            summaryGenerationError = "No incomplete action items to export."
            return
        }

        Task {
            let service = RemindersExportService()
            do {
                let count = try await service.exportToReminders(
                    actionItems: items,
                    sessionTitle: session.title
                )
                Self.logger.info("Exported \(count) action items to Reminders")
                exportSuccessMessage = "Exported \(count) action items to Reminders."
            } catch {
                Self.logger.error("Reminders export failed: \(error.localizedDescription)")
                summaryGenerationError = error.localizedDescription
            }
        }
    }

    private func exportActionItemsToCalendar() {
        guard let session else { return }
        let items = session.actionItems.filter { !$0.isCompleted && $0.dueDate != nil }
        guard !items.isEmpty else {
            summaryGenerationError = "No action items with due dates to export."
            return
        }

        Task {
            let service = RemindersExportService()
            do {
                let count = try await service.exportToCalendar(
                    actionItems: items,
                    sessionTitle: session.title
                )
                Self.logger.info("Exported \(count) action items to Calendar")
                exportSuccessMessage = "Exported \(count) events to Calendar."
            } catch {
                Self.logger.error("Calendar export failed: \(error.localizedDescription)")
                summaryGenerationError = error.localizedDescription
            }
        }
    }

    private func exportAudio(session: RecordingSession) {
        let urls = session.audioFileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        let baseName = urls[0].deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName).m4a"

        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isExportingAudio = true
        Task {
            do {
                try await AudioExporter.mergeAndExport(urls: urls, to: destURL)
            } catch {
                Self.logger.error("Audio export failed: \(error.localizedDescription)")
                fetchError = "Failed to save audio: \(error.localizedDescription)"
            }
            isExportingAudio = false
        }
    }

    // MARK: - Chat Panel

    private var chatPanelMode: ChatPanelMode {
        ChatPanelMode(rawValue: chatPanelModeRaw) ?? .inline
    }

    private var isInlineChat: Bool {
        isChatOpen && chatPanelMode == .inline
    }

    private func toggleChat() {
        if isChatOpen {
            closeChat()
        } else {
            openChat()
        }
    }

    private func openChat() {
        ensureChatViewModel()
        // Auto-select windowed mode if window is too narrow
        if detailWidth < DS.Layout.narrowWindowThreshold {
            chatPanelModeRaw = ChatPanelMode.window.rawValue
        }
        isChatOpen = true
        if chatPanelMode == .window {
            presentChatWindow()
        }
        Self.logger.info("Chat opened in \(chatPanelMode.rawValue) mode")
    }

    private func closeChat() {
        isChatOpen = false
        dismissChatWindow()
        Self.logger.info("Chat closed")
    }

    private func switchChatMode(_ mode: ChatPanelMode) {
        guard chatPanelMode != mode else {
            // Same mode — just toggle open
            if !isChatOpen { openChat() }
            return
        }
        dismissChatWindow()
        chatPanelModeRaw = mode.rawValue
        if !isChatOpen {
            openChat()
        } else if mode == .window {
            presentChatWindow()
        }
        Self.logger.info("Chat mode switched to \(mode.rawValue)")
    }

    private func ensureChatViewModel() {
        if chatViewModel == nil {
            chatViewModel = ChatViewModel()
        }
        chatViewModel?.configure(sessionID: sessionID, segments: sortedSegments)
    }

    private func presentChatWindow() {
        guard chatWindowController == nil else {
            chatWindowController?.window?.makeKeyAndOrderFront(nil)
            return
        }
        let container = modelContext.container
        let title = session?.title ?? "Untitled"
        let controller = ChatWindowController(
            viewModel: chatViewModel!,
            sessionTitle: title,
            modelContainer: container
        )
        controller.onClose = {
            isChatOpen = false
            chatWindowController = nil
        }
        // Position relative to main window
        if let mainWindow = NSApp.mainWindow {
            controller.positionRelativeTo(mainWindow.frame)
        }
        controller.showWindow(nil)
        chatWindowController = controller
    }

    private func dismissChatWindow() {
        chatWindowController?.window?.close()
        chatWindowController = nil
    }
}

// MARK: - PreferenceKey

private struct DetailWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
