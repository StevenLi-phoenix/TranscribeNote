import Foundation
import os

nonisolated final class SummarizerService: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "SummarizerService")

    private let engine: any LLMEngine
    private static let retryDelays: [TimeInterval] = [10, 30, 60]

    init(engine: any LLMEngine) {
        self.engine = engine
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

        let prompt = PromptBuilder.buildSummarizationPrompt(
            segments: segments,
            previousSummary: previousSummary,
            config: config
        )

        Self.logger.info("Starting summarization (\(segments.count) segments, \(totalText.count) chars)")

        var lastError: Error?

        for attempt in 0..<3 {
            do {
                let result = try await engine.generate(prompt: prompt, config: llmConfig)
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.info("Summarization succeeded on attempt \(attempt + 1) (\(trimmed.count) chars)")
                return trimmed
            } catch {
                lastError = error
                Self.logger.warning("Summarization attempt \(attempt + 1) failed: \(error.localizedDescription)")

                // Only retry on network/HTTP errors
                if !Self.isRetryable(error) {
                    Self.logger.error("Non-retryable error, aborting")
                    throw error
                }

                // Wait before retry (except after last attempt)
                if attempt < 2 {
                    let delay = Self.retryDelays[attempt]
                    Self.logger.info("Retrying in \(Int(delay))s...")
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        Self.logger.error("All 3 summarization attempts failed")
        throw lastError!
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let llmError = error as? LLMEngineError {
            switch llmError {
            case .networkError, .httpError:
                return true
            case .invalidURL, .decodingError, .emptyResponse, .notConfigured:
                return false
            }
        }
        return true // Unknown errors are retryable
    }
}
