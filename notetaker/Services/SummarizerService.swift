import Foundation
import os

nonisolated final class SummarizerService: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "SummarizerService")

    private let engine: any LLMEngine
    private static let retryDelays: [TimeInterval] = [10, 30, 60]

    init(engine: any LLMEngine) {
        self.engine = engine
    }

    /// Core retry logic for LLM generation with exponential backoff.
    private func retryableGenerate(messages: [LLMMessage], llmConfig: LLMConfig, label: String = "generation") async throws -> LLMMessage {
        var lastError: Error?

        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let result = try await engine.generate(messages: messages, config: llmConfig)
                let trimmedContent = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.info("\(label) succeeded on attempt \(attempt + 1) (\(trimmedContent.count) chars)")
                if let usage = result.usage {
                    Self.logger.info("\(label) tokens: input=\(usage.inputTokens) output=\(usage.outputTokens) cache_create=\(usage.cacheCreationTokens) cache_read=\(usage.cacheReadTokens)")
                }
                return LLMMessage(role: .assistant, content: trimmedContent, usage: result.usage)
            } catch is CancellationError {
                Self.logger.info("\(label) cancelled on attempt \(attempt + 1)")
                throw CancellationError()
            } catch {
                lastError = error
                Self.logger.warning("\(label) attempt \(attempt + 1) failed: \(error.localizedDescription)")

                if !Self.isRetryable(error) {
                    Self.logger.error("Non-retryable error in \(label), aborting")
                    throw error
                }

                if attempt < 2 {
                    let delay = Self.retryDelays[attempt]
                    Self.logger.info("Retrying \(label) in \(Int(delay))s...")
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        Self.logger.error("All 3 \(label) attempts failed")
        throw lastError!
    }

    /// Core retry logic for structured LLM generation with exponential backoff.
    private func retryableGenerateStructured(messages: [LLMMessage], schema: JSONSchema, llmConfig: LLMConfig, label: String = "structured generation") async throws -> StructuredOutput {
        var lastError: Error?

        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let result = try await engine.generateStructured(messages: messages, schema: schema, config: llmConfig)
                Self.logger.info("\(label) succeeded on attempt \(attempt + 1) (\(result.data.count) bytes)")
                if let usage = result.usage {
                    Self.logger.info("\(label) tokens: input=\(usage.inputTokens) output=\(usage.outputTokens) cache_create=\(usage.cacheCreationTokens) cache_read=\(usage.cacheReadTokens)")
                }
                return result
            } catch is CancellationError {
                Self.logger.info("\(label) cancelled on attempt \(attempt + 1)")
                throw CancellationError()
            } catch {
                lastError = error
                Self.logger.warning("\(label) attempt \(attempt + 1) failed: \(error.localizedDescription)")

                if !Self.isRetryable(error) {
                    Self.logger.error("Non-retryable error in \(label), aborting")
                    throw error
                }

                if attempt < 2 {
                    let delay = Self.retryDelays[attempt]
                    Self.logger.info("Retrying \(label) in \(Int(delay))s...")
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        Self.logger.error("All 3 \(label) attempts failed")
        throw lastError!
    }

    func summarize(
        segments: [TranscriptSegment],
        previousSummary: String?,
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) async throws -> String {
        // Guard: minimum transcript length
        let totalText = segments.map(\.text).joined(separator: " ")
        guard totalText.count >= config.minTranscriptLength else {
            Self.logger.info("Transcript too short (\(totalText.count) < \(config.minTranscriptLength)), skipping summarization")
            return ""
        }

        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: previousSummary,
            config: config
        )

        Self.logger.info("Starting summarization (\(segments.count) segments, \(totalText.count) chars)")
        let result = try await retryableGenerate(messages: messages, llmConfig: llmConfig, label: "summarization")
        return result.content
    }

    /// Regenerate a summary with additional user instructions (guided regeneration).
    func summarizeWithInstructions(
        segments: [TranscriptSegment],
        instructions: String,
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) async throws -> String {
        let messages = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: nil,
            config: config,
            additionalInstructions: instructions
        )

        Self.logger.info("Starting guided regeneration (\(segments.count) segments, instructions: \(instructions.prefix(60)))")
        let result = try await retryableGenerate(messages: messages, llmConfig: llmConfig, label: "guided regeneration")
        return result.content
    }

    /// Generate a short descriptive title from transcript segments.
    func generateTitle(
        segments: [TranscriptSegment],
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) async throws -> String {
        guard !segments.isEmpty else { return "" }

        let messages = PromptBuilder.buildTitlePrompt(segments: segments, config: config)
        Self.logger.info("Starting title generation (\(segments.count) segments)")
        let result = try await retryableGenerate(messages: messages, llmConfig: llmConfig, label: "title generation")
        // Clean up: remove surrounding quotes if any
        let cleaned = result.content.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}"))
        return cleaned
    }

    /// Extract action items from transcript segments using LLM.
    /// Prefers structured output (JSON schema) when the engine supports it; falls back to free-text + parser.
    func extractActionItems(
        segments: [TranscriptSegment],
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) async throws -> [ActionItemParser.RawActionItem] {
        guard !segments.isEmpty else { return [] }

        let totalText = segments.map(\.text).joined(separator: " ")
        guard totalText.count >= config.minTranscriptLength else {
            Self.logger.info("Transcript too short for action item extraction (\(totalText.count) chars)")
            return []
        }

        let messages = PromptBuilder.buildActionItemExtractionPrompt(segments: segments, config: config)
        Self.logger.info("Starting action item extraction (\(segments.count) segments, \(totalText.count) chars)")

        // Try structured output first for reliable JSON
        if engine.supportsStructuredOutput, let schema = ActionItemParser.jsonSchema {
            do {
                let structured = try await engine.generateStructured(messages: messages, schema: schema, config: llmConfig)
                if let usage = structured.usage {
                    Self.logger.info("action item extraction (structured) tokens: input=\(usage.inputTokens) output=\(usage.outputTokens)")
                }
                let items = try structured.decode([ActionItemParser.RawActionItem].self)
                Self.logger.info("Structured output: \(items.count) action items")
                return items.filter { !$0.content.isEmpty }
            } catch {
                Self.logger.warning("Structured output failed, falling back to free-text: \(error.localizedDescription)")
            }
        }

        // Fallback: free-text generation + parser
        let result = try await retryableGenerate(messages: messages, llmConfig: llmConfig, label: "action item extraction")
        return ActionItemParser.parse(result.content)
    }

    /// Try structured summary generation. Returns nil if engine doesn't support it or generation fails.
    func summarizeStructured(
        segments: [TranscriptSegment],
        previousSummary: String?,
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) async throws -> StructuredSummary? {
        guard engine.supportsStructuredOutput else {
            Self.logger.info("Engine does not support structured output, skipping")
            return nil
        }

        let totalText = segments.map(\.text).joined(separator: " ")
        guard totalText.count >= config.minTranscriptLength else {
            Self.logger.info("Transcript too short for structured summarization (\(totalText.count) < \(config.minTranscriptLength))")
            return nil
        }

        let messages = PromptBuilder.buildStructuredSummarizationPrompt(
            segments: segments,
            previousSummary: previousSummary,
            config: config
        )

        Self.logger.info("Starting structured summarization (\(segments.count) segments, \(totalText.count) chars)")
        let output = try await retryableGenerateStructured(
            messages: messages,
            schema: SummarySchemaProvider.schema,
            llmConfig: llmConfig,
            label: "structured summarization"
        )
        return try output.decode(StructuredSummary.self)
    }

    /// Summarize with structured output when available, falling back to plain text.
    /// Returns (content, structuredSummary?) — content is always populated.
    func summarizeWithFallback(
        segments: [TranscriptSegment],
        previousSummary: String?,
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) async throws -> (content: String, structured: StructuredSummary?) {
        // Try structured output first
        do {
            if let structured = try await summarizeStructured(
                segments: segments,
                previousSummary: previousSummary,
                config: config,
                llmConfig: llmConfig
            ) {
                Self.logger.info("Structured summarization succeeded, using structured.summary as content")
                return (content: structured.summary, structured: structured)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.warning("Structured summarization failed, falling back to plain text: \(error.localizedDescription)")
        }

        // Fallback to plain text
        let content = try await summarize(
            segments: segments,
            previousSummary: previousSummary,
            config: config,
            llmConfig: llmConfig
        )
        return (content: content, structured: nil)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let llmError = error as? LLMEngineError {
            switch llmError {
            case .networkError:
                return true
            case .httpError(let statusCode, _):
                return statusCode >= 500 || statusCode == 429
            case .invalidURL, .decodingError, .emptyResponse, .notConfigured, .notSupported, .schemaError, .toolExecutionError, .maxIterationsReached:
                return false
            }
        }
        return true // Unknown errors are retryable
    }

    /// Split segments into time-window chunks by intervalMinutes, with window indices.
    /// Windows are zero-based: window 0 = [0, interval), window 1 = [interval, 2*interval), etc.
    /// Returns (windowIndex, segments) pairs for each non-empty window.
    static func splitIntoChunksWithWindowIndices(
        segments: [TranscriptSegment],
        intervalMinutes: Int
    ) -> [(windowIndex: Int, segments: [TranscriptSegment])] {
        guard !segments.isEmpty, intervalMinutes > 0 else { return [] }

        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        let sorted = segments.sorted { $0.startTime < $1.startTime }

        let lastEnd = sorted[sorted.count - 1].endTime
        let windowCount = max(1, Int(ceil(lastEnd / intervalSeconds)))

        var chunks: [[TranscriptSegment]] = Array(repeating: [], count: windowCount)
        for segment in sorted {
            let windowIndex = min(
                Int(segment.startTime / intervalSeconds),
                windowCount - 1
            )
            chunks[windowIndex].append(segment)
        }

        return chunks.enumerated().compactMap { index, segs in
            segs.isEmpty ? nil : (windowIndex: index, segments: segs)
        }
    }

    /// Split segments into time-window chunks by intervalMinutes.
    /// Segments are assigned to the zero-based window containing their startTime.
    /// Empty windows are filtered out.
    static func splitIntoChunks(
        segments: [TranscriptSegment],
        intervalMinutes: Int
    ) -> [[TranscriptSegment]] {
        splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: intervalMinutes)
            .map(\.segments)
    }

    /// Summarize segments in time-window chunks, yielding a ChunkProgress for each.
    /// Chunks are processed sequentially so each uses the previous as context.
    /// Non-retryable errors (e.g. misconfigured API key) terminate the stream with a throw.
    /// Retryable errors that exhaust all retries are logged and the chunk is skipped.
    func summarizeInChunks(
        segments: [TranscriptSegment],
        intervalMinutes: Int,
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) -> AsyncThrowingStream<ChunkProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let intervalSeconds = TimeInterval(intervalMinutes * 60)
                let indexedChunks = Self.splitIntoChunksWithWindowIndices(segments: segments, intervalMinutes: intervalMinutes)
                let totalChunks = indexedChunks.count
                Self.logger.info("Chunked summarization: \(totalChunks) chunks from \(segments.count) segments (interval: \(intervalMinutes)m)")

                let sorted = segments.sorted { $0.startTime < $1.startTime }
                let lastEnd = sorted.last?.endTime ?? 0

                var previousSummary: String?

                for (index, entry) in indexedChunks.enumerated() {
                    guard !Task.isCancelled else {
                        Self.logger.info("Chunked summarization cancelled at chunk \(index + 1)/\(totalChunks)")
                        break
                    }

                    let coveringFrom = TimeInterval(entry.windowIndex) * intervalSeconds
                    let isLastChunk = (index == indexedChunks.count - 1)
                    let coveringTo = isLastChunk
                        ? lastEnd
                        : TimeInterval(entry.windowIndex + 1) * intervalSeconds

                    do {
                        let content = try await self.summarize(
                            segments: entry.segments,
                            previousSummary: previousSummary,
                            config: config,
                            llmConfig: llmConfig
                        )
                        guard !content.isEmpty else { continue }

                        let progress = ChunkProgress(
                            chunkIndex: index,
                            totalChunks: totalChunks,
                            content: content,
                            coveringFrom: coveringFrom,
                            coveringTo: coveringTo
                        )
                        continuation.yield(progress)
                        previousSummary = content
                    } catch {
                        if !Self.isRetryable(error) {
                            Self.logger.error("Non-retryable error on chunk \(index + 1)/\(totalChunks): \(error.localizedDescription). Aborting.")
                            continuation.finish(throwing: error)
                            return
                        }
                        Self.logger.error("Chunk \(index + 1)/\(totalChunks) failed after retries: \(error.localizedDescription)")
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Synthesize chunk summaries into a single overall summary.
    func summarizeOverall(
        chunkSummaries: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)],
        config: SummarizerConfig,
        llmConfig: LLMConfig
    ) async throws -> String {
        guard !chunkSummaries.isEmpty else {
            Self.logger.info("No chunk summaries to synthesize, returning empty")
            return ""
        }

        let totalText = chunkSummaries.map(\.content).joined(separator: " ")
        guard totalText.count >= config.minTranscriptLength else {
            Self.logger.info("Overall text too short (\(totalText.count) < \(config.minTranscriptLength)), skipping overall summarization")
            return ""
        }

        let messages = PromptBuilder.buildOverallSummaryPrompt(
            chunkSummaries: chunkSummaries,
            config: config
        )

        Self.logger.info("Starting overall summarization (\(chunkSummaries.count) chunks, \(totalText.count) chars)")
        let result = try await retryableGenerate(messages: messages, llmConfig: llmConfig, label: "overall summarization")
        return result.content
    }
}

/// Progress update emitted during chunked summarization.
nonisolated struct ChunkProgress: Sendable {
    let chunkIndex: Int
    let totalChunks: Int
    let content: String
    let coveringFrom: TimeInterval
    let coveringTo: TimeInterval
}
