import Foundation
import os

/// Analyzes transcript text for emotional sentiment using LLM.
nonisolated enum SentimentAnalyzer {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SentimentAnalyzer")

    /// Recognized sentiment categories.
    enum Sentiment: String, CaseIterable, Sendable {
        case neutral = "neutral"
        case positive = "positive"
        case negative = "negative"
        case urgent = "urgent"
        case confused = "confused"

        /// SF Symbol name for the sentiment.
        var symbolName: String {
            switch self {
            case .neutral: return "minus.circle.fill"
            case .positive: return "face.smiling.fill"
            case .negative: return "exclamationmark.circle.fill"
            case .urgent: return "bolt.circle.fill"
            case .confused: return "questionmark.circle.fill"
            }
        }
    }

    /// Data carrier for segments to analyze.
    struct SegmentData: Sendable {
        let index: Int
        let text: String
    }

    /// Build a prompt for batch sentiment analysis of multiple segments.
    static func buildPrompt(segments: [SegmentData]) -> String {
        var prompt = """
        Classify the sentiment of each numbered transcript segment. \
        Reply with ONLY a comma-separated list of sentiments, one per segment, in order. \
        Valid sentiments: neutral, positive, negative, urgent, confused.

        Example input:
        1: "Great job on the launch!"
        2: "We need to fix this by tomorrow."

        Example output:
        positive, urgent

        Now classify:

        """
        for seg in segments {
            // Sanitize text: strip newlines, limit length to prevent prompt injection
            let sanitized = seg.text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .prefix(200)
            prompt += "\(seg.index + 1): \"\(sanitized)\"\n"
        }
        return prompt
    }

    /// Parse LLM response into sentiment values.
    static func parseResponse(_ response: String, expectedCount: Int) -> [Sentiment] {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let parts = cleaned.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var results = [Sentiment]()
        for part in parts {
            if let sentiment = Sentiment(rawValue: part) {
                results.append(sentiment)
            } else {
                results.append(.neutral) // Default fallback
            }
        }

        // Pad or truncate to expected count
        while results.count < expectedCount {
            results.append(.neutral)
        }
        if results.count > expectedCount {
            results = Array(results.prefix(expectedCount))
        }

        logger.debug("Parsed \(results.count) sentiments from response")
        return results
    }

    /// Analyze a batch of segments using LLM.
    static func analyzeBatch(
        segments: [SegmentData],
        engine: any LLMEngine,
        config: LLMConfig
    ) async throws -> [Sentiment] {
        guard !segments.isEmpty else { return [] }

        let prompt = buildPrompt(segments: segments)
        let messages = [
            LLMMessage(role: .system, content: "You are a sentiment classifier. Respond only with comma-separated sentiment labels."),
            LLMMessage(role: .user, content: prompt),
        ]

        let response = try await engine.generate(messages: messages, config: config)
        let sentiments = parseResponse(response.content, expectedCount: segments.count)

        logger.info("Analyzed batch of \(segments.count) segments")
        return sentiments
    }
}
