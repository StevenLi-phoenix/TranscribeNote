import Foundation

enum PromptBuilder {
    /// Sanitize user-provided language string: strip newlines, filter to letters/spaces only, limit length.
    private static func sanitizeLanguage(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = String(cleaned.unicodeScalars.filter {
            CharacterSet.letters.union(.whitespaces).contains($0)
        })
        return String(filtered.prefix(50))
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
    ) -> [LLMMessage] {
        var messages: [LLMMessage] = []

        // System message: role + format + constraints (stable across calls, cache candidate)
        let task = config.summaryStyle == .lectureNotes
            ? "Create detailed, structured notes from the following transcript segment."
            : "Summarize the following transcript."
        let (role, format) = styleInstructions(style: config.summaryStyle, task: task)

        let systemParts = [role, format, constraintBlock(config: config)]

        messages.append(LLMMessage(role: .system, content: systemParts.joined(separator: "\n\n"), cacheHint: true))

        // Additional user instructions placed in user message to reduce prompt injection risk
        if let additionalInstructions, !additionalInstructions.isEmpty {
            let sanitized = sanitizeInstructions(additionalInstructions)
            messages.append(LLMMessage(role: .user, content: "Additional user instructions: \(sanitized)"))
        }

        // Previous context as a separate user message (stable for retries, cache candidate)
        if config.includeContext, let previousSummary, !previousSummary.isEmpty {
            let truncated = String(previousSummary.prefix(config.maxContextTokens))
            let contextLabel = config.summaryStyle == .lectureNotes
                ? "Previous notes for context:"
                : "Previous summary for context:"
            messages.append(LLMMessage(role: .user, content: "\(contextLabel)\n\(truncated)", cacheHint: true))
        }

        // Transcript content (changes each call)
        var transcriptParts: [String] = []
        if !segments.isEmpty {
            transcriptParts.append("Transcript:")
            for segment in segments {
                let timestamp = segment.startTime.mmss
                transcriptParts.append("[\(timestamp)] \(segment.text)")
            }
        }
        if !transcriptParts.isEmpty {
            messages.append(LLMMessage(role: .user, content: transcriptParts.joined(separator: "\n\n")))
        }

        return messages
    }

    /// Build a prompt to generate a concise session title from transcript segments.
    static func buildTitlePrompt(
        segments: [TranscriptSegment],
        config: SummarizerConfig
    ) -> [LLMMessage] {
        var messages: [LLMMessage] = []

        // System instructions (stable, cache candidate)
        var systemParts = [
            "You are a concise title generator. Generate a short, descriptive title (5-10 words max) for the following transcript.",
            "Output ONLY the title text. Do not include quotes, punctuation at the end, or any preamble."
        ]

        if config.summaryLanguage != "auto" {
            let lang = sanitizeLanguage(config.summaryLanguage)
            systemParts.append("IMPORTANT: Write the title in \(lang).")
        }

        messages.append(LLMMessage(role: .system, content: systemParts.joined(separator: "\n\n"), cacheHint: true))

        // Transcript content
        if !segments.isEmpty {
            var parts = ["Transcript:"]
            for segment in segments.prefix(50) {
                let timestamp = segment.startTime.mmss
                parts.append("[\(timestamp)] \(segment.text)")
            }
            if segments.count > 50 {
                parts.append("... (\(segments.count - 50) more segments)")
            }
            messages.append(LLMMessage(role: .user, content: parts.joined(separator: "\n\n")))
        }

        return messages
    }

    /// Build a prompt to extract structured action items from transcript segments as JSON.
    static func buildActionItemExtractionPrompt(
        segments: [TranscriptSegment],
        config: SummarizerConfig
    ) -> [LLMMessage] {
        var messages: [LLMMessage] = []

        // System: instruct JSON array output (stable, cache candidate)
        var systemParts = [
            "You are an action item extractor. Analyze the transcript and extract all action items, decisions, and follow-up tasks.",
            """
            Output a JSON array with this exact structure (no other text, no code fences):
            [
              {
                "content": "description of the action item",
                "category": "task" or "decision" or "followUp",
                "assignee": "person name" or null,
                "dueDate": "YYYY-MM-DD" or null
              }
            ]
            """,
            """
            Categories:
            - "task": concrete actions someone needs to do
            - "decision": decisions that were made during the discussion
            - "followUp": items that need future follow-up or checking
            """,
            "If there are no action items, return an empty array: []"
        ]

        if config.summaryLanguage != "auto" {
            let lang = sanitizeLanguage(config.summaryLanguage)
            systemParts.append("IMPORTANT: Write the action item content in \(lang).")
        }

        messages.append(LLMMessage(role: .system, content: systemParts.joined(separator: "\n\n"), cacheHint: true))

        // Transcript content
        if !segments.isEmpty {
            var parts = ["Transcript:"]
            for segment in segments {
                let timestamp = segment.startTime.mmss
                let speaker = segment.speakerLabel.map { "[\($0)] " } ?? ""
                parts.append("[\(timestamp)] \(speaker)\(segment.text)")
            }
            messages.append(LLMMessage(role: .user, content: parts.joined(separator: "\n")))
        }

        return messages
    }

    static func buildOverallSummaryPrompt(
        chunkSummaries: [(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String)],
        config: SummarizerConfig
    ) -> [LLMMessage] {
        var messages: [LLMMessage] = []

        // System instructions (stable, cache candidate)
        let task = config.summaryStyle == .lectureNotes
            ? "Synthesize the following section summaries into comprehensive, structured notes."
            : "Synthesize the following section summaries into a single cohesive overall summary."
        let (role, format) = styleInstructions(style: config.summaryStyle, task: task)

        let systemContent = [role, format, constraintBlock(config: config)].joined(separator: "\n\n")
        messages.append(LLMMessage(role: .system, content: systemContent, cacheHint: true))

        // Section summaries as user content
        if !chunkSummaries.isEmpty {
            var parts = ["Section summaries:"]
            for chunk in chunkSummaries {
                let from = chunk.coveringFrom.mmss
                let to = chunk.coveringTo.mmss
                parts.append("[\(from) – \(to)]\n\(chunk.content)")
            }
            messages.append(LLMMessage(role: .user, content: parts.joined(separator: "\n\n")))
        }

        return messages
    }
}
