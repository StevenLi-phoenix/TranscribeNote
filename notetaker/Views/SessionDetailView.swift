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
    @State private var refreshTimer: Timer?
    @State private var isExportingAudio = false
    @AppStorage("overallSummaryCollapsed") private var overallCollapsed = false
    @AppStorage("overallSummaryHeight") private var overallHeight: Double = 300
    @AppStorage("chunkSummariesHidden") private var chunkSummariesHidden = false
    @State private var showChatPanel = false
    @State private var showActionItemsPopover = false
    @State private var exportSuccessMessage: String?
    @AppStorage("chatPanelWidth") private var chatPanelWidth: Double = 320

    var body: some View {
        if isLoading {
            ProgressView()
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
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(DS.Typography.callout)
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

                        if session.audioFileURLs.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
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

                        if !session.actionItems.isEmpty {
                            Button {
                                showActionItemsPopover.toggle()
                            } label: {
                                Label("Action Items (\(session.actionItems.count))", systemImage: "checklist.checked")
                            }
                            .help("View extracted action items")
                            .popover(isPresented: $showActionItemsPopover, arrowEdge: .bottom) {
                                ActionItemListView(
                                    actionItems: session.actionItems.sorted { $0.createdAt < $1.createdAt },
                                    sessionTitle: session.title,
                                    onExportReminders: { exportActionItemsToReminders() },
                                    onExportCalendar: { exportActionItemsToCalendar() }
                                )
                                .frame(width: 400, height: 350)
                            }
                        }

                        Button {
                            withAnimation { showChatPanel.toggle() }
                        } label: {
                            Label("Chat", systemImage: showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
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

                // Overall summary (collapsible + resizable)
                if let overall = session.summaries.first(where: { $0.isOverall }) {
                    Divider()
                    VStack(spacing: 0) {
                        Button {
                            withAnimation { overallCollapsed.toggle() }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: overallCollapsed ? "chevron.right" : "chevron.down")
                                    .font(DS.Typography.caption)
                                    .frame(width: 12)
                                Text("Overall Summary")
                                    .font(DS.Typography.sectionHeader)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .padding(.vertical, DS.Spacing.xs)

                        if !overallCollapsed {
                            ScrollView {
                                SummaryCardView(
                                    block: overall,
                                    onSave: { newContent in
                                        saveEditedSummary(block: overall, content: newContent)
                                    },
                                    onRegenerate: { instructions in
                                        regenerateSummary(block: overall, instructions: instructions)
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            .frame(maxHeight: overallHeight)

                            ResizeHandle(height: $overallHeight, minHeight: 80, maxHeight: 600)
                        }
                    }
                }

                Divider()

                // Transcript with optional inline chunk summaries
                if sortedSegments.isEmpty {
                    ContentUnavailableView(
                        "No Transcript",
                        systemImage: "text.bubble",
                        description: Text("This session has no transcript segments")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    // Chunk summaries toggle (only shown when chunk summaries exist)
                    if session.summaries.contains(where: { !$0.isOverall }) {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation { chunkSummariesHidden.toggle() }
                            } label: {
                                Label(
                                    chunkSummariesHidden ? "Show Summaries" : "Hide Summaries",
                                    systemImage: chunkSummariesHidden ? "eye.slash" : "eye"
                                )
                                .font(DS.Typography.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.vertical, DS.Spacing.xxs)
                        }
                    }

                    TranscriptView(
                        segments: sortedSegments,
                        partialText: "",
                        summaries: chunkSummariesHidden ? [] : session.summaries.filter { !$0.isOverall },
                        scrollToTime: $scrollToTime
                    )
                }

            }
            .frame(maxWidth: .infinity)

            if showChatPanel {
                VerticalResizeHandle(width: $chatPanelWidth, minWidth: 250, maxWidth: 500)
                ChatView(segments: sortedSegments, sessionID: sessionID)
                    .frame(width: chatPanelWidth)
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
                isLoading = true
                isGeneratingSummary = false
                summaryGenerationError = nil
                summaryProgress = nil
                scrollToTime = nil
                showChatPanel = false
                showActionItemsPopover = false
                exportSuccessMessage = nil
                fetchSession()
            }
            .onDisappear {
                playbackService.stop()
                summaryTask?.cancel()
                refreshTimer?.invalidate()
                refreshTimer = nil
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
                try? modelContext.save()

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
                try? modelContext.save()
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

}
