import Testing
import Foundation
@testable import notetaker

@Suite("KeychainMigration Extended Tests", .serialized)
struct KeychainMigrationExtendedTests {

    private static let suiteName = "com.notetaker.test.KeychainMigrationExtendedTests"
    private let migrationKey = "keychainMigrationCompleted_v1"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)!
        cleanUp()
    }

    private func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
        for key in ["liveLLMConfigJSON", "overallLLMConfigJSON", "llmConfigJSON"] {
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
        defaults.set(legacyJSON, forKey: "liveLLMConfigJSON")

        KeychainMigration.migrateIfNeeded(defaults: defaults)

        // API key should be in Keychain
        let keychainKey = LLMConfig.keychainKey(for: "liveLLMConfigJSON")
        let stored = KeychainService.load(key: keychainKey)
        #expect(stored == "sk-legacy-key")

        // JSON in UserDefaults should no longer contain apiKey
        if let newJSON = defaults.string(forKey: "liveLLMConfigJSON") {
            #expect(!newJSON.contains("sk-legacy-key"))
        }

        // Migration flag should be set
        #expect(defaults.bool(forKey: migrationKey) == true)
    }

    @Test func migrateIfNeededSkipsWhenAlreadyCompleted() {
        cleanUp()
        defer { cleanUp() }

        defaults.set(true, forKey: migrationKey)

        // Set up config that should NOT be migrated
        let legacyJSON = """
        {"provider":"openAI","model":"gpt-4","apiKey":"should-not-migrate","baseURL":"https://api.openai.com/v1","temperature":0.7,"maxTokens":4096}
        """
        defaults.set(legacyJSON, forKey: "liveLLMConfigJSON")

        KeychainMigration.migrateIfNeeded(defaults: defaults)

        // Should NOT have been migrated to Keychain
        let keychainKey = LLMConfig.keychainKey(for: "liveLLMConfigJSON")
        #expect(KeychainService.load(key: keychainKey) == nil)
    }

    @Test func migrateIfNeededHandlesMissingConfig() {
        cleanUp()
        defer { cleanUp() }

        // No config keys set — migration should complete without error
        KeychainMigration.migrateIfNeeded(defaults: defaults)
        #expect(defaults.bool(forKey: migrationKey) == true)
    }

    @Test func migrateIfNeededHandlesEmptyApiKey() {
        cleanUp()
        defer { cleanUp() }

        let legacyJSON = """
        {"provider":"custom","model":"local","apiKey":"","baseURL":"http://localhost:1234/v1","temperature":0.7,"maxTokens":4096}
        """
        defaults.set(legacyJSON, forKey: "llmConfigJSON")

        KeychainMigration.migrateIfNeeded(defaults: defaults)

        // No key should be stored
        let keychainKey = LLMConfig.keychainKey(for: "llmConfigJSON")
        #expect(KeychainService.load(key: keychainKey) == nil)
        #expect(defaults.bool(forKey: migrationKey) == true)
    }

    @Test func migrateIfNeededHandlesInvalidJSON() {
        cleanUp()
        defer { cleanUp() }

        defaults.set("not valid json", forKey: "liveLLMConfigJSON")

        // Should not crash
        KeychainMigration.migrateIfNeeded(defaults: defaults)
        #expect(defaults.bool(forKey: migrationKey) == true)
    }

    @Test func migrateIfNeededMigratesMultipleKeys() {
        cleanUp()
        defer { cleanUp() }

        let liveJSON = """
        {"provider":"openAI","model":"gpt-4","apiKey":"sk-live","baseURL":"https://api.openai.com/v1","temperature":0.7,"maxTokens":4096}
        """
        let overallJSON = """
        {"provider":"anthropic","model":"claude-3","apiKey":"sk-overall","baseURL":"https://api.anthropic.com","temperature":0.5,"maxTokens":8192}
        """
        defaults.set(liveJSON, forKey: "liveLLMConfigJSON")
        defaults.set(overallJSON, forKey: "overallLLMConfigJSON")

        KeychainMigration.migrateIfNeeded(defaults: defaults)

        #expect(KeychainService.load(key: LLMConfig.keychainKey(for: "liveLLMConfigJSON")) == "sk-live")
        #expect(KeychainService.load(key: LLMConfig.keychainKey(for: "overallLLMConfigJSON")) == "sk-overall")
    }
}
