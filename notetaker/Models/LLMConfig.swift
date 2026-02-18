import Foundation

nonisolated struct LLMConfig: Codable, Sendable, Equatable {
    var provider: LLMProvider
    var model: String
    var apiKey: String
    var baseURL: String
    var temperature: Double
    var maxTokens: Int

    static let `default` = LLMConfig(
        provider: .custom,
        model: "qwen3-14b-mlx",
        apiKey: "",
        baseURL: "http://localhost:1234/v1",
        temperature: 0.7,
        maxTokens: 4096
    )

    /// Load from UserDefaults, falling back to `.default`.
    static func fromUserDefaults(key: String = "llmConfigJSON") -> LLMConfig {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(LLMConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
