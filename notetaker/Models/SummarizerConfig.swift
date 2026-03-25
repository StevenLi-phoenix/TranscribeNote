import Foundation

nonisolated struct SummarizerConfig: Codable, Sendable, Equatable {
    var liveSummarizationEnabled: Bool
    var intervalMinutes: Int
    var minTranscriptLength: Int
    var summaryLanguage: String
    var summaryStyle: SummaryStyle
    var includeContext: Bool
    var maxContextTokens: Int
    var overallSummaryMode: OverallSummaryMode

    static let `default` = SummarizerConfig(
        liveSummarizationEnabled: true,
        intervalMinutes: 1,
        minTranscriptLength: 100,
        summaryLanguage: "auto",
        summaryStyle: .bullets,
        includeContext: true,
        maxContextTokens: 2000,
        overallSummaryMode: .auto
    )

    init(
        liveSummarizationEnabled: Bool = true,
        intervalMinutes: Int = 1,
        minTranscriptLength: Int = 100,
        summaryLanguage: String = "auto",
        summaryStyle: SummaryStyle = .bullets,
        includeContext: Bool = true,
        maxContextTokens: Int = 2000,
        overallSummaryMode: OverallSummaryMode = .auto
    ) {
        self.liveSummarizationEnabled = liveSummarizationEnabled
        self.intervalMinutes = intervalMinutes
        self.minTranscriptLength = minTranscriptLength
        self.summaryLanguage = summaryLanguage
        self.summaryStyle = summaryStyle
        self.includeContext = includeContext
        self.maxContextTokens = maxContextTokens
        self.overallSummaryMode = overallSummaryMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liveSummarizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveSummarizationEnabled) ?? true
        intervalMinutes = try container.decode(Int.self, forKey: .intervalMinutes)
        minTranscriptLength = try container.decode(Int.self, forKey: .minTranscriptLength)
        summaryLanguage = try container.decode(String.self, forKey: .summaryLanguage)
        summaryStyle = try container.decode(SummaryStyle.self, forKey: .summaryStyle)
        includeContext = try container.decode(Bool.self, forKey: .includeContext)
        maxContextTokens = try container.decode(Int.self, forKey: .maxContextTokens)
        overallSummaryMode = try container.decodeIfPresent(OverallSummaryMode.self, forKey: .overallSummaryMode) ?? .auto
    }

    /// Load from UserDefaults, falling back to `.default`.
    static func fromUserDefaults(key: String = "summarizerConfigJSON") -> SummarizerConfig {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(SummarizerConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
