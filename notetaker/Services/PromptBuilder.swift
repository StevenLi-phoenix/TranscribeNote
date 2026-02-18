enum PromptBuilder {
    static func buildSummarizationPrompt(
        segments: [TranscriptSegment],
        previousSummary: String?,
        config: SummarizerConfig
    ) -> String {
        var parts: [String] = []

        // System instruction
        parts.append("You are a meeting/note summarizer. Summarize the following transcript.")

        // Style instruction
        switch config.summaryStyle {
        case .bullets:
            parts.append("Format your response as concise bullet points.")
        case .paragraph:
            parts.append("Format your response as a coherent paragraph summary.")
        case .actionItems:
            parts.append("Extract action items as a checklist using - [ ] format.")
        }

        // Language instruction
        if config.summaryLanguage != "auto" {
            parts.append("Respond in \(config.summaryLanguage).")
        }

        // Previous context
        if config.includeContext, let previousSummary, !previousSummary.isEmpty {
            let truncated = String(previousSummary.prefix(config.maxContextTokens))
            parts.append("Previous summary for context:\n\(truncated)")
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
}
