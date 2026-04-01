import Testing
import Foundation
@testable import TranscribeNote

@Suite("KeychainMigration", .serialized)
struct KeychainMigrationTests {

    private static let suiteName = "com.transcribenote.test.KeychainMigrationTests"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)!
    }

    @Test
    func encodedConfigExcludesApiKey() throws {
        let config = LLMConfig(apiKey: "sk-secret-key-12345")
        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8)!

        #expect(!json.contains("apiKey"))
        #expect(!json.contains("sk-secret"))
    }

    @Test
    func decodedConfigHasEmptyApiKey() throws {
        let json = """
        {"provider":"custom","model":"gpt-4","baseURL":"http://localhost","temperature":0.5,"maxTokens":1024}
        """
        let config = try JSONDecoder().decode(LLMConfig.self, from: json.data(using: .utf8)!)
        #expect(config.apiKey == "")
        #expect(config.model == "gpt-4")
    }

    @Test
    func keychainKeyMapping() {
        #expect(LLMConfig.keychainKey(for: "liveLLMConfigJSON") == "transcribenote.live.apiKey")
        #expect(LLMConfig.keychainKey(for: "overallLLMConfigJSON") == "transcribenote.overall.apiKey")
        #expect(LLMConfig.keychainKey(for: "llmConfigJSON") == "transcribenote.legacy.apiKey")
        #expect(LLMConfig.keychainKey(for: "unknownKey") == "transcribenote.unknownKey.apiKey")
    }
}
