import Foundation
import os

extension Notification.Name {
    static let llmConfigDidSave = Notification.Name("notetaker.llmConfigDidSave")
}

nonisolated struct LLMConfig: Codable, Sendable, Equatable {
    var provider: LLMProvider
    var model: String
    var apiKey: String
    var baseURL: String
    var temperature: Double
    var maxTokens: Int
    var thinkingEnabled: Bool

    // Exclude apiKey from JSON encoding/decoding — it lives in Keychain
    private enum CodingKeys: String, CodingKey {
        case provider, model, baseURL, temperature, maxTokens, thinkingEnabled
    }

    init(provider: LLMProvider = .custom, model: String = "qwen3-14b-mlx", apiKey: String = "", baseURL: String = "http://localhost:1234/v1", temperature: Double = 0.7, maxTokens: Int = 4096, thinkingEnabled: Bool = false) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.thinkingEnabled = thinkingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(LLMProvider.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        temperature = try container.decode(Double.self, forKey: .temperature)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        thinkingEnabled = try container.decodeIfPresent(Bool.self, forKey: .thinkingEnabled) ?? false
        apiKey = "" // Hydrated from Keychain separately
    }

    static let `default` = LLMConfig(
        provider: .custom,
        model: "qwen3-14b-mlx",
        apiKey: "",
        baseURL: "http://localhost:1234/v1",
        temperature: 0.7,
        maxTokens: 4096,
        thinkingEnabled: false
    )

    /// Maps a UserDefaults config key to its Keychain account name.
    static func keychainKey(for configKey: String) -> String {
        switch configKey {
        case "liveLLMConfigJSON": return "notetaker.live.apiKey"
        case "overallLLMConfigJSON": return "notetaker.overall.apiKey"
        case "titleLLMConfigJSON": return "notetaker.title.apiKey"
        case "llmConfigJSON": return "notetaker.legacy.apiKey"
        default: return "notetaker.\(configKey).apiKey"
        }
    }

    /// Load from UserDefaults + Keychain, falling back to `.default`.
    static func fromUserDefaults(key: String = "llmConfigJSON") -> LLMConfig {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              var config = try? JSONDecoder().decode(LLMConfig.self, from: data) else {
            return .default
        }
        // Hydrate apiKey from Keychain
        config.apiKey = KeychainService.load(key: keychainKey(for: key)) ?? ""
        return config
    }

    /// Save config JSON to UserDefaults and apiKey to Keychain.
    static func save(_ config: LLMConfig, to key: String) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMConfig")
        guard let data = try? JSONEncoder().encode(config),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Failed to encode LLMConfig for key '\(key)'")
            return
        }
        UserDefaults.standard.set(json, forKey: key)
        KeychainService.save(key: keychainKey(for: key), value: config.apiKey)
        logger.debug("Saved LLMConfig to '\(key)' (apiKey in Keychain)")
    }
}
