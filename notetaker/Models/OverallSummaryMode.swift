nonisolated enum OverallSummaryMode: String, Codable, CaseIterable, Sendable {
    /// Use all raw transcript segments (token-heavy, most accurate)
    case rawText
    /// Use existing chunk summaries only (token-efficient)
    case chunkSummaries
    /// Use chunks if available, else fall back to raw text
    case auto
}
