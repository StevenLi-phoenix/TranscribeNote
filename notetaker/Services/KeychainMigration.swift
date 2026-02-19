import Foundation
import os

nonisolated enum KeychainMigration {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "KeychainMigration")
    private static let migrationKey = "keychainMigrationCompleted_v1"

    /// One-time migration: extract apiKey from UserDefaults JSON and move to Keychain.
    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            logger.debug("Keychain migration already completed")
            return
        }

        logger.info("Starting Keychain migration...")

        let configKeys = ["liveLLMConfigJSON", "overallLLMConfigJSON", "llmConfigJSON"]

        for configKey in configKeys {
            migrateKey(configKey)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        logger.info("Keychain migration completed")
    }

    private static func migrateKey(_ configKey: String) {
        guard let json = UserDefaults.standard.string(forKey: configKey),
              let data = json.data(using: .utf8) else {
            return
        }

        // Decode with legacy struct that includes apiKey
        guard let legacy = try? JSONDecoder().decode(LegacyLLMConfig.self, from: data) else {
            logger.warning("Failed to decode legacy config for '\(configKey)'")
            return
        }

        guard !legacy.apiKey.isEmpty else {
            logger.debug("No apiKey to migrate for '\(configKey)'")
            return
        }

        // Save apiKey to Keychain
        let keychainKey = LLMConfig.keychainKey(for: configKey)
        KeychainService.save(key: keychainKey, value: legacy.apiKey)
        logger.info("Migrated apiKey for '\(configKey)' to Keychain key '\(keychainKey)'")

        // Re-encode without apiKey (LLMConfig.CodingKeys excludes it)
        let config = LLMConfig(
            provider: legacy.provider,
            model: legacy.model,
            apiKey: "",
            baseURL: legacy.baseURL,
            temperature: legacy.temperature,
            maxTokens: legacy.maxTokens
        )
        if let newData = try? JSONEncoder().encode(config),
           let newJSON = String(data: newData, encoding: .utf8) {
            UserDefaults.standard.set(newJSON, forKey: configKey)
            logger.debug("Re-encoded '\(configKey)' without apiKey")
        }
    }
}

/// Legacy config struct that includes apiKey in JSON for migration decoding.
private nonisolated struct LegacyLLMConfig: Codable, Sendable {
    let provider: LLMProvider
    let model: String
    let apiKey: String
    let baseURL: String
    let temperature: Double
    let maxTokens: Int
}
