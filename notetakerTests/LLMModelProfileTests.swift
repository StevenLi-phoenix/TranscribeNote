import Testing
import Foundation
@testable import notetaker

@Suite("LLMModelProfile Tests", .serialized)
struct LLMModelProfileTests {

    /// Helper to clean up all profile-related UserDefaults and Keychain keys.
    private func cleanUpDefaults() {
        UserDefaults.standard.removeObject(forKey: "llmModelProfilesJSON")
        for key in ["liveLLMConfigJSON", "overallLLMConfigJSON", "titleLLMConfigJSON", "llmConfigJSON"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for role in LLMRole.allCases {
            UserDefaults.standard.removeObject(forKey: role.profileIDKey)
            UserDefaults.standard.removeObject(forKey: role.inheritsLiveKey)
        }
    }

    // MARK: - LLMModelProfile

    @Test func initDefaults() {
        let profile = LLMModelProfile(name: "Test")
        #expect(profile.name == "Test")
        #expect(profile.config == .default)
        #expect(!profile.id.uuidString.isEmpty)
    }

    @Test func initCustomConfig() {
        let config = LLMConfig(provider: .anthropic, model: "claude-3", apiKey: "sk-123", baseURL: "https://api.anthropic.com")
        let id = UUID()
        let profile = LLMModelProfile(id: id, name: "Claude", config: config)
        #expect(profile.id == id)
        #expect(profile.name == "Claude")
        #expect(profile.config.provider == .anthropic)
        #expect(profile.config.model == "claude-3")
    }

    @Test func keychainKeyFormat() {
        let id = UUID()
        let profile = LLMModelProfile(id: id, name: "Test")
        #expect(profile.keychainKey == "notetaker.profile.\(id.uuidString).apiKey")
    }

    @Test func equatable() {
        let id = UUID()
        let a = LLMModelProfile(id: id, name: "Test", config: .default)
        let b = LLMModelProfile(id: id, name: "Test", config: .default)
        #expect(a == b)
    }

    @Test func codableRoundTrip() throws {
        let profile = LLMModelProfile(name: "Encodable", config: LLMConfig(provider: .openAI, model: "gpt-4"))
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LLMModelProfile.self, from: data)
        #expect(decoded.id == profile.id)
        #expect(decoded.name == profile.name)
        #expect(decoded.config.provider == .openAI)
        #expect(decoded.config.model == "gpt-4")
        // apiKey should be empty after decode (excluded from CodingKeys)
        #expect(decoded.config.apiKey == "")
    }

    // MARK: - LLMRole

    @Test func roleDisplayNames() {
        #expect(LLMRole.live.displayName == "Live Summarization")
        #expect(LLMRole.overall.displayName == "Overall Summary")
        #expect(LLMRole.title.displayName == "Title Generation")
    }

    @Test func roleSubtitles() {
        #expect(!LLMRole.live.subtitle.isEmpty)
        #expect(!LLMRole.overall.subtitle.isEmpty)
        #expect(!LLMRole.title.subtitle.isEmpty)
    }

    @Test func roleProfileIDKey() {
        #expect(LLMRole.live.profileIDKey == "liveLLMProfileID")
        #expect(LLMRole.overall.profileIDKey == "overallLLMProfileID")
        #expect(LLMRole.title.profileIDKey == "titleLLMProfileID")
    }

    @Test func roleInheritsLiveKey() {
        #expect(LLMRole.live.inheritsLiveKey == "liveLLMInheritsLive")
        #expect(LLMRole.overall.inheritsLiveKey == "overallLLMInheritsLive")
        #expect(LLMRole.title.inheritsLiveKey == "titleLLMInheritsLive")
    }

    @Test func allCases() {
        #expect(LLMRole.allCases.count == 3)
        #expect(LLMRole.allCases.contains(.live))
        #expect(LLMRole.allCases.contains(.overall))
        #expect(LLMRole.allCases.contains(.title))
    }

    // MARK: - LLMProfileStore

    @Test func assignedProfileIDRoundTrip() {
        cleanUpDefaults()
        defer { cleanUpDefaults() }

        let id = UUID()
        LLMProfileStore.setAssignedProfileID(id, for: .live)
        #expect(LLMProfileStore.assignedProfileID(for: .live) == id)

        // Clear
        LLMProfileStore.setAssignedProfileID(nil, for: .live)
        #expect(LLMProfileStore.assignedProfileID(for: .live) == nil)
    }

    @Test func inheritsLiveDefaultFalse() {
        cleanUpDefaults()
        defer { cleanUpDefaults() }

        #expect(LLMProfileStore.inheritsLive(for: .overall) == false)
    }

    @Test func inheritsLiveAlwaysFalseForLive() {
        cleanUpDefaults()
        defer { cleanUpDefaults() }

        // .live role should always return false regardless of setting
        LLMProfileStore.setInheritsLive(true, for: .live)
        #expect(LLMProfileStore.inheritsLive(for: .live) == false)
    }

    @Test func inheritsLiveRoundTrip() {
        cleanUpDefaults()
        defer { cleanUpDefaults() }

        // Use .title role (less commonly used by other test suites) to minimize cross-suite races
        LLMProfileStore.setInheritsLive(true, for: .title)
        #expect(LLMProfileStore.inheritsLive(for: .title) == true)
        LLMProfileStore.setInheritsLive(false, for: .title)
        #expect(LLMProfileStore.inheritsLive(for: .title) == false)
    }

    @Test func resolveConfigFallsBackToDefault() {
        // Clear all profiles and assignments
        UserDefaults.standard.removeObject(forKey: "llmModelProfilesJSON")
        for role in LLMRole.allCases {
            UserDefaults.standard.removeObject(forKey: role.profileIDKey)
            UserDefaults.standard.removeObject(forKey: role.inheritsLiveKey)
        }
        // Clear legacy keys too
        for key in ["liveLLMConfigJSON", "overallLLMConfigJSON", "titleLLMConfigJSON", "llmConfigJSON"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        let config = LLMProfileStore.resolveConfig(for: .live)
        // Should get .default config (possibly through migration that creates a default profile)
        #expect(config.provider == .custom)
        #expect(config.model == "qwen3-14b-mlx")
    }

    @Test func saveAndLoadProfiles() {
        let profiles = [
            LLMModelProfile(name: "Profile1", config: LLMConfig(provider: .ollama, model: "llama3")),
            LLMModelProfile(name: "Profile2", config: LLMConfig(provider: .openAI, model: "gpt-4")),
        ]
        LLMProfileStore.saveProfiles(profiles)
        let loaded = LLMProfileStore.loadProfiles()
        #expect(loaded.count == 2)
        #expect(loaded[0].name == "Profile1")
        #expect(loaded[1].name == "Profile2")
        #expect(loaded[0].config.provider == .ollama)
        #expect(loaded[1].config.provider == .openAI)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "llmModelProfilesJSON")
    }

    @Test func deleteProfileClearsRoleAssignment() {
        var profiles = [
            LLMModelProfile(name: "ToDelete", config: .default)
        ]
        LLMProfileStore.saveProfiles(profiles)
        let id = profiles[0].id
        LLMProfileStore.setAssignedProfileID(id, for: .live)

        LLMProfileStore.deleteProfile(id: id, from: &profiles)
        #expect(profiles.isEmpty)
        #expect(LLMProfileStore.assignedProfileID(for: .live) == nil)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "llmModelProfilesJSON")
    }
}
