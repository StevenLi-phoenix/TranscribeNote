import Foundation

enum PromptBuilder {
    /// Sanitize user-provided language string: strip newlines, limit length.
    private static func sanitizeLanguage(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(50))
    }

    /// Sanitize user-provided instructions: strip control characters, limit length.
    private static func sanitizeInstructions(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(500))
    }

    /// Constraint block: no preamble + language enforcement.
    private static func constraintBlock(config: SummarizerConfig) -> String {
        var lines = ["Output ONLY the summary content. Do not include any preamble, introduction, or meta-commentary."]
        if config.summaryLanguage != "auto" {
            let lang = sanitizeLanguage(config.summaryLanguage)
            lines.append("IMPORTANT: You MUST write the entire response in \(lang). Do not use any other language.")
        }
        return lines.joined(separator: " ")
    }

    /// Style-specific system role and format instructions.
    private static func styleInstructions(style: SummaryStyle, task: String) -> (role: String, format: String) {
        switch style {
        case .bullets:
            return (
                "You are a meeting/note summarizer. \(task)",
                "Format your response as concise bullet points."
            )
        case .paragraph:
            return (
                "You are a meeting/note summarizer. \(task)",
                "Format your response as a coherent paragraph summary."
            )
        case .actionItems:
            return (
                "You are a meeting/note summarizer. \(task)",
                "Extract action items as a checklist using - [ ] format."
            )
        case .lectureNotes:
            return (
                "You are a meticulous lecture note-taker. "
                + "\(task) "
                + "Capture every key concept, definition, example, and argument. "
                + "Do not omit details — these notes should let someone who missed the lecture fully understand the material.",
                "Format your response as detailed bullet points grouped by topic. "
                + "Use nested bullets for supporting details and examples. "
                + "Start each top-level bullet with a bold topic header using **Topic:** format."
            )
        }
    }

    static func buildSummarizationPrompt(
        segments: [TranscriptSegment],
        previousSummary: String?,
        config: SummarizerConfig,
        additionalInstructions: String? = nil
    ) -> String {
        var parts: [String] = []

        let task = config.summaryStyle == .lectureNotes
            ? "Create detailed, structured notes from the following transcript segment."
            : "Summarize the following transcript."
        let (role, format) = styleInstructions(style: config.summaryStyle, task: task)
        parts.append(role)
        parts.append(format)

        // Constraints: no preamble + language
        parts.append(constraintBlock(config: config))

        // Additional user instructions for guided regeneration
        if let additionalInstructions, !additionalInstructions.isEmpty {
            let sanitized = sanitizeInstructions(additionalInstructions)
            parts.append("Additional user instructions: \(sanitized)")
        }

        // Previous context — label varies by style
        if config.includeContext, let previousSummary, !previousSummary.isEmpty {
            let truncated = String(previousSummary.prefix(config.maxContextTokens))
            let contextLabel = config.summaryStyle == .lectureNotes
                ? "Previous notes for context:"
                : "Previous summary for context:"
            parts.append("\(contextLabel)\n\(truncated)")
        }

        // Timestamped transcript
        if !segments.isEmpty {
            parts.append("Transcript:")
            for segment in segments {
                let timestamp = segment.startTime.mmss
                parts.append("[\(timestamp)] \(segment.text)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    /// Build a prompt to generate a concise session title from transcript segments.
    static func buildTitlePrompt(
        segments: [TranscriptSegment],
        config: SummarizerConfig
    ) -> String {
        var parts: [String] = []

        parts.append("You are a concise title generator. Generate a short, descriptive title (5-10 words max) for the following transcript.")
        parts.append("Output ONLY the title text. Do not include quotes, punctuation at the end, or any preamble.")

        if config.summaryLanguage != "auto" {
            let lang = sanitizeLanguage(config.summaryLanguage)
            parts.append("IMPORTANT: Write the title in \(lang).")
        }

        if !segments.isEmpty {
            parts.append("Transcript:")
            for segment in segments.prefix(50) {
                let timestamp = segment.startTime.mmss
                parts.append("[\(timestamp)] \(segment.text)")
            }
            if segments.count > 50 {
                parts.append("... (\(segments.count - 50) more segments)")
            }
        }

        return parts.joined(separator: "\n\n")
    }

    static func buildOverallSummaryPrompt(
        chunkSummaries: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)],
        config: SummarizerConfig
    ) -> String {
        var parts: [String] = []

        let task = config.summaryStyle == .lectureNotes
            ? "Synthesize the following section summaries into comprehensive, structured notes."
            : "Synthesize the following section summaries into a single cohesive overall summary."
        let (role, format) = styleInstructions(style: config.summaryStyle, task: task)
        parts.append(role)
        parts.append(format)

        // Constraints: no preamble + language
        parts.append(constraintBlock(config: config))

        // Section summaries with time ranges
        if !chunkSummaries.isEmpty {
            parts.append("Section summaries:")
            for chunk in chunkSummaries {
                let from = chunk.coveringFrom.mmss
                let to = chunk.coveringTo.mmss
                parts.append("[\(from) – \(to)]\n\(chunk.content)")
            }
        }

        return parts.joined(separator: "\n\n")
    }
}
