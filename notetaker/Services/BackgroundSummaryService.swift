import Foundation
import SwiftData
import os

/// Generates post-recording summaries in a background task independent of view lifecycle.
/// Uses its own ModelContext so summaries are persisted even if the user navigates away.
@MainActor
final class BackgroundSummaryService {
    static let shared = BackgroundSummaryService()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "BackgroundSummaryService"
    )

    /// Currently running background summary task, keyed by session ID.
    private(set) var activeTasks: [UUID: Task<Void, Never>] = [:]

    /// Currently running action item extraction task, keyed by session ID.
    private(set) var activeActionItemTasks: [UUID: Task<Void, Never>] = [:]

    /// Currently running sentiment analysis task, keyed by session ID.
    private(set) var activeSentimentTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    /// Whether a background summary is in progress for the given session.
    func isRunning(for sessionID: UUID) -> Bool {
        activeTasks[sessionID] != nil
    }

    /// Whether action item extraction is in progress for the given session.
    func isExtractingActionItems(for sessionID: UUID) -> Bool {
        activeActionItemTasks[sessionID] != nil
    }

    /// Wait for all active background tasks to complete (used for graceful quit).
    func awaitAll() async {
        for (_, task) in activeTasks {
            await task.value
        }
        for (_, task) in activeActionItemTasks {
            await task.value
        }
        for (_, task) in activeSentimentTasks {
            await task.value
        }
    }

    /// Cancel all active background tasks immediately (used for fast quit).
    func cancelAll() {
        for (id, task) in activeTasks {
            Self.logger.info("Cancelling background summary for \(id)")
            task.cancel()
        }
        activeTasks.removeAll()
        for (id, task) in activeActionItemTasks {
            Self.logger.info("Cancelling action item extraction for \(id)")
            task.cancel()
        }
        activeActionItemTasks.removeAll()
        for (id, task) in activeSentimentTasks {
            Self.logger.info("Cancelling sentiment analysis for \(id)")
            task.cancel()
        }
        activeSentimentTasks.removeAll()
    }

    /// Fire-and-forget: generate an overall summary for a just-completed recording session.
    func dispatchOverallSummary(sessionID: UUID, container: ModelContainer) {
        // Don't double-dispatch
        guard activeTasks[sessionID] == nil else {
            Self.logger.info("Background summary already running for session \(sessionID)")
            return
        }

        Self.logger.info("Dispatching background summary for session \(sessionID)")

        let task = Task { @MainActor [weak self] in
            defer { self?.activeTasks.removeValue(forKey: sessionID) }

            let context = container.mainContext
            let llmConfig = LLMProfileStore.resolveConfig(for: .overall)
            let summarizerConfig = SummarizerConfig.fromUserDefaults()
            let engine = await LLMEngineFactory.createWithFallback(from: llmConfig)
            let service = SummarizerService(engine: engine)

            let predicate = #Predicate<RecordingSession> { $0.id == sessionID }
            guard let session = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
                Self.logger.error("Session \(sessionID) not found for background summary")
                return
            }

            let segments = session.segments.sorted { $0.startTime < $1.startTime }
            guard !segments.isEmpty else {
                Self.logger.info("No segments for session \(sessionID), skipping summary")
                return
            }

            // Check for existing chunk summaries from live periodic summarization
            let chunkSummaries = session.summaries.filter { !$0.isOverall && !$0.isPinned && !$0.userEdited }

            do {
                var content: String
                var structuredResult: StructuredSummary?
                let sortedChunks = chunkSummaries
                    .sorted { $0.coveringFrom < $1.coveringFrom }
                    .map { (coveringFrom: $0.coveringFrom, coveringTo: $0.coveringTo, content: $0.content) }

                switch summarizerConfig.overallSummaryMode {
                case .rawText:
                    Self.logger.info("Mode: rawText — generating from transcript for \(sessionID)")
                    let result = try await service.summarizeWithFallback(
                        segments: segments,
                        previousSummary: nil,
                        config: summarizerConfig,
                        llmConfig: llmConfig
                    )
                    content = result.content
                    structuredResult = result.structured
                case .chunkSummaries:
                    if sortedChunks.isEmpty {
                        Self.logger.warning("Mode: chunkSummaries but no chunks available, falling back to raw text for \(sessionID)")
                        let result = try await service.summarizeWithFallback(
                            segments: segments,
                            previousSummary: nil,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                        content = result.content
                        structuredResult = result.structured
                    } else {
                        Self.logger.info("Mode: chunkSummaries — synthesizing \(sortedChunks.count) chunks for \(sessionID) (structured output not available for chunk synthesis)")
                        content = try await service.summarizeOverall(
                            chunkSummaries: sortedChunks,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                    }
                case .auto:
                    if chunkSummaries.isEmpty {
                        Self.logger.info("Mode: auto, no chunks — generating from transcript for \(sessionID)")
                        let result = try await service.summarizeWithFallback(
                            segments: segments,
                            previousSummary: nil,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                        content = result.content
                        structuredResult = result.structured
                    } else {
                        Self.logger.info("Mode: auto — synthesizing \(sortedChunks.count) chunks for \(sessionID) (structured output not available for chunk synthesis)")
                        content = try await service.summarizeOverall(
                            chunkSummaries: sortedChunks,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                    }
                }

                guard !Task.isCancelled, !content.isEmpty else { return }

                // Re-fetch session after async work
                guard let currentSession = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
                    Self.logger.error("Session \(sessionID) deleted during background summary")
                    return
                }

                // Remove old auto-generated overall summaries
                for existing in currentSession.summaries where existing.isOverall && !existing.isPinned && !existing.userEdited {
                    context.delete(existing)
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
                context.insert(block)

                try context.save()
                Self.logger.info("Background summary saved for session \(sessionID) (\(content.count) chars)")

                // Generate title after summary
                await Self.generateTitle(
                    sessionID: sessionID,
                    segments: segments,
                    context: context,
                    summarizerConfig: summarizerConfig
                )
            } catch is CancellationError {
                Self.logger.info("Background summary cancelled for \(sessionID)")
            } catch {
                Self.logger.error("Background summary failed for \(sessionID): \(error.localizedDescription)")

                // Still try title generation even if summary failed
                await Self.generateTitle(
                    sessionID: sessionID,
                    segments: segments,
                    context: context,
                    summarizerConfig: summarizerConfig
                )
            }
        }

        activeTasks[sessionID] = task
    }

    /// Fire-and-forget: extract action items for a just-completed recording session.
    func dispatchActionItemExtraction(sessionID: UUID, container: ModelContainer) {
        guard activeActionItemTasks[sessionID] == nil else {
            Self.logger.info("Action item extraction already running for session \(sessionID)")
            return
        }

        Self.logger.info("Dispatching action item extraction for session \(sessionID)")

        let task = Task { @MainActor [weak self] in
            defer { self?.activeActionItemTasks.removeValue(forKey: sessionID) }

            let context = container.mainContext
            let llmConfig = LLMProfileStore.resolveConfig(for: .actionItems)
            let summarizerConfig = SummarizerConfig.fromUserDefaults()
            let engine = await LLMEngineFactory.createWithFallback(from: llmConfig)
            let service = SummarizerService(engine: engine)

            let predicate = #Predicate<RecordingSession> { $0.id == sessionID }
            guard let session = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
                Self.logger.error("Session \(sessionID) not found for action item extraction")
                return
            }

            let segments = session.segments.sorted { $0.startTime < $1.startTime }
            guard !segments.isEmpty else {
                Self.logger.info("No segments for session \(sessionID), skipping action item extraction")
                return
            }

            do {
                let rawItems = try await service.extractActionItems(
                    segments: segments,
                    config: summarizerConfig,
                    llmConfig: llmConfig
                )

                guard !Task.isCancelled, !rawItems.isEmpty else { return }

                // Re-fetch session after async work
                guard let currentSession = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
                    Self.logger.error("Session \(sessionID) deleted during action item extraction")
                    return
                }

                // Remove old auto-extracted action items (keep user-modified ones)
                for existing in currentSession.actionItems {
                    context.delete(existing)
                }

                for raw in rawItems {
                    let item = ActionItem(
                        content: raw.content,
                        dueDate: ActionItemParser.parseDate(raw.dueDate),
                        assignee: raw.assignee,
                        category: ActionItemCategory(rawValue: raw.category) ?? .task
                    )
                    item.session = currentSession
                    context.insert(item)
                }

                try context.save()
                Self.logger.info("Extracted \(rawItems.count) action items for session \(sessionID)")
            } catch is CancellationError {
                Self.logger.info("Action item extraction cancelled for \(sessionID)")
            } catch {
                Self.logger.error("Action item extraction failed for \(sessionID): \(error.localizedDescription)")
            }
        }

        activeActionItemTasks[sessionID] = task
    }

    /// Fire-and-forget: analyze sentiment for transcript segments of a just-completed recording session.
    func dispatchSentimentAnalysis(sessionID: UUID, container: ModelContainer) {
        guard activeSentimentTasks[sessionID] == nil else {
            Self.logger.info("Sentiment analysis already running for session \(sessionID)")
            return
        }

        Self.logger.info("Dispatching sentiment analysis for session \(sessionID)")

        let task = Task { @MainActor [weak self] in
            defer { self?.activeSentimentTasks.removeValue(forKey: sessionID) }

            let context = container.mainContext
            let llmConfig = LLMProfileStore.resolveConfig(for: .live)
            let engine = await LLMEngineFactory.createWithFallback(from: llmConfig)

            let predicate = #Predicate<RecordingSession> { $0.id == sessionID }
            guard let session = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
                Self.logger.error("Session \(sessionID) not found for sentiment analysis")
                return
            }

            let segments = session.segments
                .sorted { $0.startTime < $1.startTime }
                .filter { $0.sentiment == nil }
            guard !segments.isEmpty else {
                Self.logger.info("No untagged segments for session \(sessionID), skipping sentiment analysis")
                return
            }

            // Process in batches of 20 to avoid overly long prompts
            let batchSize = 20
            var taggedCount = 0
            for batchStart in stride(from: 0, to: segments.count, by: batchSize) {
                guard !Task.isCancelled else { break }

                let batchEnd = min(batchStart + batchSize, segments.count)
                let batch = Array(segments[batchStart..<batchEnd])
                let segmentData = batch.enumerated().map {
                    SentimentAnalyzer.SegmentData(index: $0.offset, text: $0.element.text)
                }

                do {
                    let sentiments = try await SentimentAnalyzer.analyzeBatch(
                        segments: segmentData,
                        engine: engine,
                        config: llmConfig
                    )

                    for (i, sentiment) in sentiments.enumerated() where i < batch.count {
                        batch[i].sentiment = sentiment.rawValue
                    }
                    taggedCount += sentiments.count
                } catch is CancellationError {
                    Self.logger.info("Sentiment analysis cancelled for \(sessionID)")
                    return
                } catch {
                    Self.logger.error("Sentiment batch failed for \(sessionID): \(error.localizedDescription)")
                    // Continue with next batch
                }
            }

            guard !Task.isCancelled, taggedCount > 0 else { return }

            do {
                try context.save()
                Self.logger.info("Sentiment analysis complete for session \(sessionID) (\(taggedCount) segments tagged)")
            } catch {
                Self.logger.error("Failed to save sentiment results for \(sessionID): \(error.localizedDescription)")
            }
        }

        activeSentimentTasks[sessionID] = task
    }

    /// Generate a descriptive title for the session using the title LLM config.
    private static func generateTitle(
        sessionID: UUID,
        segments: [TranscriptSegment],
        context: ModelContext,
        summarizerConfig: SummarizerConfig
    ) async {
        guard !segments.isEmpty else { return }

        let titleConfig = LLMProfileStore.resolveConfig(for: .title)
        let engine = await LLMEngineFactory.createWithFallback(from: titleConfig)
        let service = SummarizerService(engine: engine)

        do {
            let title = try await service.generateTitle(
                segments: segments,
                config: summarizerConfig,
                llmConfig: titleConfig
            )
            guard !Task.isCancelled, !title.isEmpty else { return }

            let predicate = #Predicate<RecordingSession> { $0.id == sessionID }
            guard let currentSession = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
                logger.error("Session \(sessionID) deleted during title generation")
                return
            }

            currentSession.title = title
            try context.save()
            logger.info("Title generated for session \(sessionID) (\(title.count) chars)")
        } catch is CancellationError {
            logger.info("Title generation cancelled for \(sessionID)")
        } catch {
            logger.error("Title generation failed for \(sessionID): \(error.localizedDescription)")
        }
    }
}
