import Foundation
import SwiftData
import os

/// Manages batch re-summarization of multiple recording sessions.
@MainActor
final class BatchResummarizeService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "BatchResummarizeService")

    /// Progress tracking for batch operations.
    nonisolated struct BatchProgress: Sendable {
        let total: Int
        let completed: Int
        let failed: Int
        let currentTitle: String?

        var isFinished: Bool { completed + failed >= total }
        var fractionComplete: Double {
            guard total > 0 else { return 0 }
            return Double(completed + failed) / Double(total)
        }
    }

    /// Result of a batch re-summarization.
    nonisolated struct BatchResult: Sendable {
        let total: Int
        let succeeded: Int
        let failed: Int
        let errors: [String]  // session titles that failed
    }

    private var currentTask: Task<BatchResult, Never>?

    var isRunning: Bool { currentTask != nil && !(currentTask!.isCancelled) }

    /// Re-summarize multiple sessions sequentially.
    func resummarize(
        sessions: [RecordingSession],
        modelContext: ModelContext,
        onProgress: @escaping @MainActor (BatchProgress) -> Void
    ) -> Task<BatchResult, Never> {
        currentTask?.cancel()

        let task = Task { @MainActor [weak self] in
            let llmConfig = LLMProfileStore.resolveConfig(for: .live)
            let summarizerConfig = SummarizerConfig.fromUserDefaults()
            let engine = LLMEngineFactory.create(from: llmConfig)
            let summarizer = SummarizerService(engine: engine)

            var completed = 0
            var failed = 0
            var errors = [String]()
            let total = sessions.count

            for session in sessions {
                if Task.isCancelled { break }

                let title = session.title.isEmpty ? "Untitled" : session.title
                onProgress(BatchProgress(total: total, completed: completed, failed: failed, currentTitle: title))

                Self.logger.info("Re-summarizing session: \(title) (\(completed + 1)/\(total))")

                do {
                    let segments = session.segments.sorted { $0.startTime < $1.startTime }
                    guard !segments.isEmpty else {
                        Self.logger.warning("Skipping session with no segments: \(title)")
                        completed += 1
                        continue
                    }

                    // Delete existing summaries
                    for summary in session.summaries {
                        modelContext.delete(summary)
                    }

                    // Generate new chunk summaries
                    var chunkSummaries: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)] = []
                    for try await chunk in summarizer.summarizeInChunks(
                        segments: segments,
                        intervalMinutes: summarizerConfig.intervalMinutes,
                        config: summarizerConfig,
                        llmConfig: llmConfig
                    ) {
                        if Task.isCancelled { break }

                        let block = SummaryBlock(
                            coveringFrom: chunk.coveringFrom,
                            coveringTo: chunk.coveringTo,
                            content: chunk.content,
                            style: summarizerConfig.summaryStyle,
                            model: llmConfig.model
                        )
                        session.summaries.append(block)
                        chunkSummaries.append((coveringFrom: chunk.coveringFrom, coveringTo: chunk.coveringTo, content: chunk.content))
                    }

                    if Task.isCancelled { break }

                    // Generate overall summary if we have chunks
                    if !chunkSummaries.isEmpty {
                        let overall = try await summarizer.summarizeOverall(
                            chunkSummaries: chunkSummaries,
                            config: summarizerConfig,
                            llmConfig: llmConfig
                        )
                        if !overall.isEmpty {
                            let overallBlock = SummaryBlock(
                                coveringFrom: chunkSummaries.first?.coveringFrom ?? 0,
                                coveringTo: chunkSummaries.last?.coveringTo ?? 0,
                                content: overall,
                                style: summarizerConfig.summaryStyle,
                                model: llmConfig.model,
                                isOverall: true
                            )
                            session.summaries.append(overallBlock)
                        }
                    }

                    try modelContext.save()
                    completed += 1
                    Self.logger.info("Successfully re-summarized: \(title)")

                } catch {
                    failed += 1
                    errors.append(title)
                    Self.logger.error("Failed to re-summarize \(title): \(error.localizedDescription)")
                }
            }

            onProgress(BatchProgress(total: total, completed: completed, failed: failed, currentTitle: nil))

            let result = BatchResult(total: total, succeeded: completed, failed: failed, errors: errors)
            self?.currentTask = nil
            return result
        }

        currentTask = task
        return task
    }

    /// Cancel the current batch operation.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        Self.logger.info("Batch re-summarization cancelled")
    }
}
