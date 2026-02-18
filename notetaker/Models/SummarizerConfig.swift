import Foundation

nonisolated struct SummarizerConfig: Codable, Sendable, Equatable {
    var intervalMinutes: Int
    var minTranscriptLength: Int
    var summaryLanguage: String
    var summaryStyle: SummaryStyle
    var includeContext: Bool
    var maxContextTokens: Int

    static let `default` = SummarizerConfig(
        intervalMinutes: 1,
        minTranscriptLength: 100,
        summaryLanguage: "auto",
        summaryStyle: .bullets,
        includeContext: true,
        maxContextTokens: 2000
    )

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
