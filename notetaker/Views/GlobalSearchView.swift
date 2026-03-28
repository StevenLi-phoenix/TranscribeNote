import SwiftUI
import SwiftData
import os

/// Cross-session knowledge search panel with Quick (full-text) and AI (RAG) modes.
struct GlobalSearchView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "GlobalSearchView")

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Callback when user taps a snippet to navigate to that session.
    var onNavigateToSession: ((UUID) -> Void)?

    enum SearchMode: String, CaseIterable {
        case quick = "Quick"
        case ai = "AI"
    }

    @State private var searchText = ""
    @State private var searchMode: SearchMode = .quick
    @State private var searchResults: [SessionSearchGroup] = []
    @State private var aiAnswer: String = ""
    @State private var isSearching = false
    @State private var isGeneratingAI = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var aiTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Knowledge Search")
                    .font(DS.Typography.title)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)

            // Search bar + mode toggle
            HStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search across all sessions...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { triggerSearch() }
                }
                .padding(DS.Spacing.sm)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: DS.Radius.md))

                Picker("Mode", selection: $searchMode) {
                    ForEach(SearchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)

            Divider()

            // Results area
            if searchText.isEmpty && searchResults.isEmpty && aiAnswer.isEmpty {
                emptyState
            } else if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        // AI answer section
                        if searchMode == .ai && !aiAnswer.isEmpty {
                            aiAnswerSection
                        }

                        if searchMode == .ai && isGeneratingAI {
                            HStack(spacing: DS.Spacing.sm) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating answer...")
                                    .font(DS.Typography.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Cancel") {
                                    aiTask?.cancel()
                                    aiTask = nil
                                    isGeneratingAI = false
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Error
                        if let searchError {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(DS.Colors.subtleError)
                                Text(searchError)
                                    .font(DS.Typography.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                        }

                        // Snippet results
                        if searchResults.isEmpty && !isSearching && !searchText.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .frame(maxWidth: .infinity)
                                .padding(.top, DS.Spacing.xxl)
                        } else {
                            snippetResultsList
                        }
                    }
                    .padding(.vertical, DS.Spacing.md)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400, idealHeight: 600)
        .onChange(of: searchText) { _, newValue in
            if searchMode == .quick {
                debounceQuickSearch(query: newValue)
            }
        }
        .onChange(of: searchMode) { _, _ in
            if searchMode == .quick && !searchText.isEmpty {
                debounceQuickSearch(query: searchText)
            }
        }
        .onDisappear {
            searchTask?.cancel()
            aiTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "Search Your Knowledge",
            systemImage: "text.magnifyingglass",
            description: Text("Search across all session transcripts and summaries.\nUse Quick mode for instant results or AI mode for intelligent answers.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var aiAnswerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("AI Answer")
                    .font(DS.Typography.sectionHeader)
            }

            Text(aiAnswer)
                .font(DS.Typography.body)
                .textSelection(.enabled)
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .padding(.horizontal, DS.Spacing.lg)
        .transition(.opacity)
    }

    private var snippetResultsList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if !searchResults.isEmpty {
                Text("Sources (\(searchResults.reduce(0) { $0 + $1.snippets.count }) matches)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Spacing.lg)
            }

            ForEach(searchResults) { group in
                sessionGroupView(group)
            }
        }
    }

    private func sessionGroupView(_ group: SessionSearchGroup) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // Session header
            HStack(spacing: DS.Spacing.xs) {
                Text(group.sessionTitle.isEmpty ? "Untitled Session" : group.sessionTitle)
                    .font(DS.Typography.sectionHeader)
                    .lineLimit(1)
                Text(group.sessionDate.formatted(date: .abbreviated, time: .shortened))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)

            // Snippets
            ForEach(group.snippets) { snippet in
                snippetRow(snippet)
            }
        }
    }

    private func snippetRow(_ snippet: SearchSnippet) -> some View {
        Button {
            // Navigate to the session containing this snippet
            if let session = fetchSession(for: snippet.sessionID) {
                onNavigateToSession?(session.id)
                dismiss()
            }
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text(snippet.segmentStartTime.mmss)
                    .font(DS.Typography.timestamp)
                    .foregroundStyle(.secondary)
                    .frame(width: DS.Layout.timestampWidth, alignment: .leading)

                highlightedText(snippet.segmentText)
                    .font(DS.Typography.body)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    /// Highlight search keywords in text.
    private func highlightedText(_ text: String) -> Text {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: searchText)
        guard !keywords.isEmpty else { return Text(text) }

        let lowered = text.lowercased()
        var result = Text("")
        var currentIndex = text.startIndex

        // Simple approach: scan through text and highlight keyword matches
        while currentIndex < text.endIndex {
            var matched = false
            for keyword in keywords {
                let remaining = text[currentIndex...]
                if remaining.lowercased().hasPrefix(keyword) {
                    let endIdx = text.index(currentIndex, offsetBy: keyword.count)
                    let matchedPortion = text[currentIndex..<endIdx]
                    result = result + Text(matchedPortion).bold().foregroundColor(.blue)
                    currentIndex = endIdx
                    matched = true
                    break
                }
            }
            if !matched {
                result = result + Text(String(text[currentIndex]))
                currentIndex = text.index(after: currentIndex)
            }
        }

        return result
    }

    // MARK: - Search Logic

    private func debounceQuickSearch(query: String) {
        searchTask?.cancel()
        aiTask?.cancel()
        isGeneratingAI = false
        aiAnswer = ""

        guard !query.isEmpty else {
            searchResults = []
            searchError = nil
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performQuickSearch(query: query)
        }
    }

    private func triggerSearch() {
        guard !searchText.isEmpty else { return }

        searchTask?.cancel()
        aiTask?.cancel()

        searchTask = Task {
            await performQuickSearch(query: searchText)

            if searchMode == .ai && !searchResults.isEmpty {
                guard !Task.isCancelled else { return }
                await performAISearch(query: searchText)
            }
        }
    }

    private func performQuickSearch(query: String) async {
        isSearching = true
        searchError = nil

        let keywords = KnowledgeSearchLogic.extractKeywords(from: query)
        guard !keywords.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        Self.logger.info("Quick search: \(keywords.count) keywords extracted from '\(query)'")

        do {
            let snippets = try searchSegments(keywords: keywords)
            let groups = KnowledgeSearchLogic.groupBySession(snippets)
            searchResults = groups
            Self.logger.info("Quick search found \(snippets.count) snippets in \(groups.count) sessions")
        } catch {
            Self.logger.error("Quick search failed: \(error.localizedDescription)")
            searchError = "Search failed: \(error.localizedDescription)"
            searchResults = []
        }

        isSearching = false
    }

    private func performAISearch(query: String) async {
        isGeneratingAI = true
        searchError = nil

        let context = KnowledgeSearchLogic.formatContext(groups: searchResults)
        guard !context.isEmpty else {
            isGeneratingAI = false
            return
        }

        Self.logger.info("AI search: generating answer for '\(query)' with \(context.count) chars context")

        let config = LLMProfileStore.resolveConfig(for: .chat)
        let engine = LLMEngineFactory.create(from: config)
        let messages = PromptBuilder.buildSearchPrompt(query: query, context: context, language: "auto")

        aiTask = Task {
            do {
                let response = try await engine.generate(messages: messages, config: config)
                guard !Task.isCancelled else { return }
                aiAnswer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let usage = response.usage {
                    Self.logger.info("AI search tokens — input: \(usage.inputTokens), output: \(usage.outputTokens)")
                }
            } catch is CancellationError {
                Self.logger.info("AI search cancelled")
            } catch {
                Self.logger.error("AI search failed: \(error.localizedDescription)")
                searchError = "AI generation failed: \(error.localizedDescription)"
            }
            isGeneratingAI = false
        }
    }

    // MARK: - SwiftData Queries

    /// Search transcript segments matching any keyword using SwiftData.
    private func searchSegments(keywords: [String]) throws -> [SearchSnippet] {
        let now = Date()
        var allSnippets: [SearchSnippet] = []

        // Fetch all sessions with their segments
        let descriptor = FetchDescriptor<RecordingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let sessions = try modelContext.fetch(descriptor)

        for session in sessions {
            for segment in session.segments {
                let score = KnowledgeSearchLogic.relevanceScore(
                    text: segment.text,
                    keywords: keywords,
                    date: session.startedAt,
                    now: now
                )
                guard score > 0 else { continue }

                allSnippets.append(SearchSnippet(
                    sessionID: session.persistentModelID,
                    sessionTitle: session.title,
                    sessionDate: session.startedAt,
                    segmentText: segment.text,
                    segmentStartTime: segment.startTime,
                    score: score
                ))
            }

            // Also search summary content
            for summary in session.summaries {
                let score = KnowledgeSearchLogic.relevanceScore(
                    text: summary.displayContent,
                    keywords: keywords,
                    date: session.startedAt,
                    now: now
                )
                guard score > 0 else { continue }

                allSnippets.append(SearchSnippet(
                    sessionID: session.persistentModelID,
                    sessionTitle: session.title,
                    sessionDate: session.startedAt,
                    segmentText: summary.displayContent,
                    segmentStartTime: summary.coveringFrom,
                    score: score
                ))
            }
        }

        // Sort by score descending and limit results
        return allSnippets
            .sorted { $0.score > $1.score }
            .prefix(100)
            .map { $0 }
    }

    /// Fetch a RecordingSession by PersistentIdentifier.
    private func fetchSession(for persistentID: PersistentIdentifier) -> RecordingSession? {
        return modelContext.registeredModel(for: persistentID) as RecordingSession?
    }
}

// Uses TimeInterval.mmss from Extensions/TimeInterval+Formatting.swift
