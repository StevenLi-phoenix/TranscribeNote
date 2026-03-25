import Testing
import Foundation
@testable import notetaker

@Suite("KeychainMigration Extended Tests", .serialized)
struct KeychainMigrationExtendedTests {

    private let migrationKey = "keychainMigrationCompleted_v1"

    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        for key in ["liveLLMConfigJSON", "overallLLMConfigJSON", "llmConfigJSON"] {
            UserDefaults.standard.removeObject(forKey: key)
            KeychainService.delete(key: LLMConfig.keychainKey(for: key))
        }
    }

    @Test func migrateIfNeededMigratesLegacyApiKey() {
        cleanUp()
        defer { cleanUp() }

        // Set up legacy config JSON with apiKey embedded
        let legacyJSON = """
        {"provider":"openAI","model":"gpt-4","apiKey":"sk-legacy-key","baseURL":"https://api.openai.com/v1","temperature":0.7,"maxTokens":4096}
        """
        UserDefaults.standard.set(legacyJSON, forKey: "liveLLMConfigJSON")

        KeychainMigration.migrateIfNeeded()

        // API key should be in Keychain
        let keychainKey = LLMConfig.keychainKey(for: "liveLLMConfigJSON")
        let stored = KeychainService.load(key: keychainKey)
        #expect(stored == "sk-legacy-key")

        // JSON in UserDefaults should no longer contain apiKey
        if let newJSON = UserDefaults.standard.string(forKey: "liveLLMConfigJSON") {
            #expect(!newJSON.contains("sk-legacy-key"))
        }

        // Migration flag should be set
        #expect(UserDefaults.standard.bool(forKey: migrationKey) == true)
    }

    @Test func migrateIfNeededSkipsWhenAlreadyCompleted() {
        cleanUp()
        defer { cleanUp() }

        UserDefaults.standard.set(true, forKey: migrationKey)

        // Set up config that should NOT be migrated
        let legacyJSON = """
        {"provider":"openAI","model":"gpt-4","apiKey":"should-not-migrate","baseURL":"https://api.openai.com/v1","temperature":0.7,"maxTokens":4096}
        """
        UserDefaults.standard.set(legacyJSON, forKey: "liveLLMConfigJSON")

        KeychainMigration.migrateIfNeeded()

        // Should NOT have been migrated to Keychain
        let keychainKey = LLMConfig.keychainKey(for: "liveLLMConfigJSON")
        #expect(KeychainService.load(key: keychainKey) == nil)
    }

    @Test func migrateIfNeededHandlesMissingConfig() {
        cleanUp()
        defer { cleanUp() }

        // No config keys set — migration should complete without error
        KeychainMigration.migrateIfNeeded()
        #expect(UserDefaults.standard.bool(forKey: migrationKey) == true)
    }

    @Test func migrateIfNeededHandlesEmptyApiKey() {
        cleanUp()
        defer { cleanUp() }

        let legacyJSON = """
        {"provider":"custom","model":"local","apiKey":"","baseURL":"http://localhost:1234/v1","temperature":0.7,"maxTokens":4096}
        """
        UserDefaults.standard.set(legacyJSON, forKey: "llmConfigJSON")

        KeychainMigration.migrateIfNeeded()

        // No key should be stored
        let keychainKey = LLMConfig.keychainKey(for: "llmConfigJSON")
        #expect(KeychainService.load(key: keychainKey) == nil)
        #expect(UserDefaults.standard.bool(forKey: migrationKey) == true)
    }

    @Test func migrateIfNeededHandlesInvalidJSON() {
        cleanUp()
        defer { cleanUp() }

        UserDefaults.standard.set("not valid json", forKey: "liveLLMConfigJSON")

        // Should not crash
        KeychainMigration.migrateIfNeeded()
        #expect(UserDefaults.standard.bool(forKey: migrationKey) == true)
    }

    // MARK: - Disabled: Cross-suite UserDefaults/Keychain race condition
    // These tests pass when run in isolation but fail non-deterministically in full
    // parallel test runs. Swift Testing lacks cross-suite serialization, so suites
    // that share UserDefaults keys (llmModelProfilesJSON, keychainMigrationCompleted_v1)
    // can overwrite each other's state. Re-enable when Swift Testing adds cross-suite
    // serialization or when tests are refactored to use isolated UserDefaults instances.
    //
    // To run manually: xcodebuild -scheme notetaker -only-testing:notetakerTests/KeychainMigrationExtendedTests/migrateIfNeededMigratesMultipleKeys test

    /*
    @Test func migrateIfNeededMigratesMultipleKeys() {
        cleanUp()
        defer { cleanUp() }

        // Double-check migration flag is clear (another suite may set it concurrently)
        UserDefaults.standard.removeObject(forKey: migrationKey)

        let liveJSON = """
        {"provider":"openAI","model":"gpt-4","apiKey":"sk-live","baseURL":"https://api.openai.com/v1","temperature":0.7,"maxTokens":4096}
        """
        let overallJSON = """
        {"provider":"anthropic","model":"claude-3","apiKey":"sk-overall","baseURL":"https://api.anthropic.com","temperature":0.5,"maxTokens":8192}
        """
        UserDefaults.standard.set(liveJSON, forKey: "liveLLMConfigJSON")
        UserDefaults.standard.set(overallJSON, forKey: "overallLLMConfigJSON")
        UserDefaults.standard.synchronize()

        KeychainMigration.migrateIfNeeded()

        #expect(KeychainService.load(key: LLMConfig.keychainKey(for: "liveLLMConfigJSON")) == "sk-live")
        #expect(KeychainService.load(key: LLMConfig.keychainKey(for: "overallLLMConfigJSON")) == "sk-overall")
    }
    */
}
