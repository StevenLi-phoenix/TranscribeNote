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
            let engine = LLMEngineFactory.create(from: llmConfig)
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
                if chunkSummaries.isEmpty {
                    // No live chunks succeeded — generate a complete summary from transcript
                    Self.logger.info("No chunk summaries, generating complete summary for \(sessionID)")
                    content = try await service.summarize(
                        segments: segments,
                        previousSummary: nil,
                        config: summarizerConfig,
                        llmConfig: llmConfig
                    )
                } else {
                    // Synthesize chunk summaries into an overall summary
                    Self.logger.info("Synthesizing \(chunkSummaries.count) chunks into overall summary for \(sessionID)")
                    let chunkInputs = chunkSummaries
                        .sorted { $0.coveringFrom < $1.coveringFrom }
                        .map { (coveringFrom: $0.coveringFrom, coveringTo: $0.coveringTo, content: $0.content) }
                    content = try await service.summarizeOverall(
                        chunkSummaries: chunkInputs,
                        config: summarizerConfig,
                        llmConfig: llmConfig
                    )
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

    /// Generate a descriptive title for the session using the title LLM config.
    private static func generateTitle(
        sessionID: UUID,
        segments: [TranscriptSegment],
        context: ModelContext,
        summarizerConfig: SummarizerConfig
    ) async {
        guard !segments.isEmpty else { return }

        let titleConfig = LLMProfileStore.resolveConfig(for: .title)
        let engine = LLMEngineFactory.create(from: titleConfig)
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
            logger.info("Title generated for session \(sessionID): \(title)")
        } catch is CancellationError {
            logger.info("Title generation cancelled for \(sessionID)")
        } catch {
            logger.error("Title generation failed for \(sessionID): \(error.localizedDescription)")
        }
    }
}
