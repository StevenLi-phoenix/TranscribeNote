import Testing
import Foundation
@testable import notetaker

@Suite("LLMConfig Tests", .serialized)
struct LLMConfigTests {

    // MARK: - Init & Defaults

    @Test func defaultValues() {
        let config = LLMConfig()
        #expect(config.provider == .custom)
        #expect(config.model == "qwen3-14b-mlx")
        #expect(config.apiKey == "")
        #expect(config.baseURL == "http://localhost:1234/v1")
        #expect(config.temperature == 0.7)
        #expect(config.maxTokens == 4096)
        #expect(config.thinkingEnabled == false)
    }

    @Test func staticDefault() {
        let config = LLMConfig.default
        #expect(config.provider == .custom)
        #expect(config.model == "qwen3-14b-mlx")
        #expect(config.temperature == 0.7)
    }

    @Test func customInit() {
        let config = LLMConfig(
            provider: .anthropic,
            model: "claude-3",
            apiKey: "sk-test",
            baseURL: "https://api.anthropic.com",
            temperature: 0.3,
            maxTokens: 8192,
            thinkingEnabled: true
        )
        #expect(config.provider == .anthropic)
        #expect(config.model == "claude-3")
        #expect(config.apiKey == "sk-test")
        #expect(config.baseURL == "https://api.anthropic.com")
        #expect(config.temperature == 0.3)
        #expect(config.maxTokens == 8192)
        #expect(config.thinkingEnabled == true)
    }

    // MARK: - Codable

    @Test func encodingExcludesApiKey() throws {
        let config = LLMConfig(apiKey: "super-secret")
        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("apiKey"))
        #expect(!json.contains("super-secret"))
    }

    @Test func decodingWithThinkingEnabled() throws {
        let json = """
        {"provider":"openAI","model":"gpt-4","baseURL":"https://api.openai.com/v1","temperature":0.5,"maxTokens":2048,"thinkingEnabled":true}
        """
        let config = try JSONDecoder().decode(LLMConfig.self, from: json.data(using: .utf8)!)
        #expect(config.thinkingEnabled == true)
        #expect(config.provider == .openAI)
    }

    @Test func decodingWithoutThinkingEnabledDefaultsFalse() throws {
        let json = """
        {"provider":"ollama","model":"llama3","baseURL":"http://localhost:11434","temperature":0.7,"maxTokens":4096}
        """
        let config = try JSONDecoder().decode(LLMConfig.self, from: json.data(using: .utf8)!)
        #expect(config.thinkingEnabled == false)
    }

    @Test func decodingAlwaysHasEmptyApiKey() throws {
        let json = """
        {"provider":"custom","model":"test","baseURL":"http://localhost","temperature":0.5,"maxTokens":1024}
        """
        let config = try JSONDecoder().decode(LLMConfig.self, from: json.data(using: .utf8)!)
        #expect(config.apiKey == "")
    }

    @Test func codableRoundTrip() throws {
        let original = LLMConfig(provider: .ollama, model: "mistral", apiKey: "ignored", baseURL: "http://localhost:11434", temperature: 0.9, maxTokens: 2048, thinkingEnabled: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMConfig.self, from: data)
        #expect(decoded.provider == .ollama)
        #expect(decoded.model == "mistral")
        #expect(decoded.baseURL == "http://localhost:11434")
        #expect(decoded.temperature == 0.9)
        #expect(decoded.maxTokens == 2048)
        #expect(decoded.thinkingEnabled == true)
        #expect(decoded.apiKey == "") // always empty after decode
    }

    // MARK: - Equatable

    @Test func equatable() {
        let a = LLMConfig(provider: .openAI, model: "gpt-4")
        let b = LLMConfig(provider: .openAI, model: "gpt-4")
        #expect(a == b)
    }

    @Test func notEqualDifferentProvider() {
        let a = LLMConfig(provider: .openAI, model: "gpt-4")
        let b = LLMConfig(provider: .anthropic, model: "gpt-4")
        #expect(a != b)
    }

    // MARK: - Keychain Key Mapping

    @Test func keychainKeyForKnownKeys() {
        #expect(LLMConfig.keychainKey(for: "liveLLMConfigJSON") == "notetaker.live.apiKey")
        #expect(LLMConfig.keychainKey(for: "overallLLMConfigJSON") == "notetaker.overall.apiKey")
        #expect(LLMConfig.keychainKey(for: "titleLLMConfigJSON") == "notetaker.title.apiKey")
        #expect(LLMConfig.keychainKey(for: "llmConfigJSON") == "notetaker.legacy.apiKey")
    }

    @Test func keychainKeyForUnknownKey() {
        #expect(LLMConfig.keychainKey(for: "myCustomKey") == "notetaker.myCustomKey.apiKey")
    }

    // MARK: - fromUserDefaults

    @Test func fromUserDefaultsReturnsDefaultWhenEmpty() {
        let key = "testLLMConfig_\(UUID().uuidString)"
        let config = LLMConfig.fromUserDefaults(key: key)
        #expect(config == .default)
    }

    @Test func fromUserDefaultsDecodesJSON() {
        let key = "testLLMConfig_\(UUID().uuidString)"
        let json = """
        {"provider":"anthropic","model":"claude-3.5","baseURL":"https://api.anthropic.com","temperature":0.3,"maxTokens":8192,"thinkingEnabled":true}
        """
        UserDefaults.standard.set(json, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let config = LLMConfig.fromUserDefaults(key: key)
        #expect(config.provider == .anthropic)
        #expect(config.model == "claude-3.5")
        #expect(config.thinkingEnabled == true)
    }

    @Test func fromUserDefaultsReturnsDefaultForInvalidJSON() {
        let key = "testLLMConfig_\(UUID().uuidString)"
        UserDefaults.standard.set("not json", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let config = LLMConfig.fromUserDefaults(key: key)
        #expect(config == .default)
    }

    // MARK: - Save

    @Test func saveAndReload() {
        let key = "testSaveLLMConfig_\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: key)
            KeychainService.delete(key: LLMConfig.keychainKey(for: key))
        }

        let config = LLMConfig(provider: .openAI, model: "gpt-4o", apiKey: "sk-test-save", baseURL: "https://api.openai.com/v1", temperature: 0.5, maxTokens: 2048)
        LLMConfig.save(config, to: key)

        let loaded = LLMConfig.fromUserDefaults(key: key)
        #expect(loaded.provider == .openAI)
        #expect(loaded.model == "gpt-4o")
        #expect(loaded.temperature == 0.5)
        #expect(loaded.maxTokens == 2048)
    }

    @Test func saveDeletesKeychainWhenApiKeyEmpty() {
        let key = "testSaveEmpty_\(UUID().uuidString)"
        let keychainKey = LLMConfig.keychainKey(for: key)
        defer {
            UserDefaults.standard.removeObject(forKey: key)
            KeychainService.delete(key: keychainKey)
        }

        // First save with key
        KeychainService.save(key: keychainKey, value: "old-key")
        #expect(KeychainService.load(key: keychainKey) == "old-key")

        // Save with empty apiKey should delete
        let config = LLMConfig(provider: .custom, model: "test", apiKey: "")
        LLMConfig.save(config, to: key)
        #expect(KeychainService.load(key: keychainKey) == nil)
    }
}
