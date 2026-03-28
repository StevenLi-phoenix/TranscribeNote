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

    private init() {}

    /// Whether a background summary is in progress for the given session.
    func isRunning(for sessionID: UUID) -> Bool {
        activeTasks[sessionID] != nil
    }

    /// Wait for all active background summaries to complete (used for graceful quit).
    func awaitAll() async {
        for (_, task) in activeTasks {
            await task.value
        }
    }

    /// Cancel all active background summaries immediately (used for fast quit).
    func cancelAll() {
        for (id, task) in activeTasks {
            Self.logger.info("Cancelling background summary for \(id)")
            task.cancel()
        }
        activeTasks.removeAll()
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
                let content: String
                let sortedChunks = chunkSummaries
                    .sorted { $0.coveringFrom < $1.coveringFrom }
                    .map { (coveringFrom: $0.coveringFrom, coveringTo: $0.coveringTo, content: $0.content) }

                switch summarizerConfig.overallSummaryMode {
                case .rawText:
                    Self.logger.info("Mode: rawText — generating from transcript for \(sessionID)")
                    content = try await service.summarize(
                        segments: segments,
                        previousSummary: nil,
                        config: summarizerConfig,
                        llmConfig: llmConfig
                    )
                case .chunkSummaries:
                    if sortedChunks.isEmpty {
                        Self.logger.warning("Mode: chunkSummaries but no chunks available, falling back to raw text for \(sessionID)")
                        content = try await service.summarize(
                            segments: segments,
                            previousSummary: nil,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                    } else {
                        Self.logger.info("Mode: chunkSummaries — synthesizing \(sortedChunks.count) chunks for \(sessionID)")
                        content = try await service.summarizeOverall(
                            chunkSummaries: sortedChunks,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                    }
                case .auto:
                    if chunkSummaries.isEmpty {
                        Self.logger.info("Mode: auto, no chunks — generating from transcript for \(sessionID)")
                        content = try await service.summarize(
                            segments: segments,
                            previousSummary: nil,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                    } else {
                        Self.logger.info("Mode: auto — synthesizing \(sortedChunks.count) chunks for \(sessionID)")
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
                    isOverall: true
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

                // Generate tags from overall summary
                await Self.generateTags(
                    sessionID: sessionID,
                    summaryContent: content,
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

    /// Generate semantic tags for the session from its overall summary.
    private static func generateTags(
        sessionID: UUID,
        summaryContent: String,
        context: ModelContext,
        summarizerConfig: SummarizerConfig
    ) async {
        guard !summaryContent.isEmpty else { return }

        let predicate = #Predicate<RecordingSession> { $0.id == sessionID }
        guard let session = try? context.fetch(FetchDescriptor(predicate: predicate)).first,
              session.tags.isEmpty else {
            return
        }

        let tagConfig = LLMProfileStore.resolveConfig(for: .title)
        let engine = await LLMEngineFactory.createWithFallback(from: tagConfig)
        let language = summarizerConfig.summaryLanguage != "auto" ? summarizerConfig.summaryLanguage : nil
        let messages = PromptBuilder.buildTagPrompt(summary: summaryContent, language: language)

        do {
            let result = try await engine.generate(messages: messages, config: tagConfig)
            let tags = TagParser.parse(from: result.content)
            guard !Task.isCancelled, !tags.isEmpty else { return }

            // Re-fetch session after async work
            guard let currentSession = try? context.fetch(FetchDescriptor(predicate: predicate)).first else {
                logger.error("Session \(sessionID) deleted during tag generation")
                return
            }

            currentSession.tags = tags
            try context.save()
            logger.info("Auto-tagged session \(sessionID) with \(tags.count) tags: \(tags.joined(separator: ", "))")
        } catch is CancellationError {
            logger.info("Tag generation cancelled for \(sessionID)")
        } catch {
            logger.warning("Tag generation failed for \(sessionID): \(error.localizedDescription)")
            // Non-fatal — session works fine without tags
        }
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
