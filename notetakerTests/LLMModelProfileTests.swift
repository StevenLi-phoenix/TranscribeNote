import Testing
import Foundation
@testable import notetaker

@Suite("LLMModelProfile Tests", .serialized)
struct LLMModelProfileTests {

    private static let suiteName = "com.notetaker.test.LLMModelProfileTests"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
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
        #expect(LLMRole.allCases.count == 5)
        #expect(LLMRole.allCases.contains(.live))
        #expect(LLMRole.allCases.contains(.overall))
        #expect(LLMRole.allCases.contains(.title))
        #expect(LLMRole.allCases.contains(.chat))
        #expect(LLMRole.allCases.contains(.actionItems))
    }

    // MARK: - LLMProfileStore

    @Test func assignedProfileIDRoundTrip() {
        let id = UUID()
        LLMProfileStore.setAssignedProfileID(id, for: .live, defaults: defaults)
        #expect(LLMProfileStore.assignedProfileID(for: .live, defaults: defaults) == id)

        // Clear
        LLMProfileStore.setAssignedProfileID(nil, for: .live, defaults: defaults)
        #expect(LLMProfileStore.assignedProfileID(for: .live, defaults: defaults) == nil)
    }

    @Test func inheritsLiveDefaultFalse() {
        #expect(LLMProfileStore.inheritsLive(for: .overall, defaults: defaults) == false)
    }

    @Test func inheritsLiveAlwaysFalseForLive() {
        // .live role should always return false regardless of setting
        LLMProfileStore.setInheritsLive(true, for: .live, defaults: defaults)
        #expect(LLMProfileStore.inheritsLive(for: .live, defaults: defaults) == false)
    }

    @Test func inheritsLiveRoundTrip() {
        LLMProfileStore.setInheritsLive(true, for: .title, defaults: defaults)
        #expect(LLMProfileStore.inheritsLive(for: .title, defaults: defaults) == true)
        LLMProfileStore.setInheritsLive(false, for: .title, defaults: defaults)
        #expect(LLMProfileStore.inheritsLive(for: .title, defaults: defaults) == false)
    }

    @Test func resolveConfigFallsBackToDefault() {
        let config = LLMProfileStore.resolveConfig(for: .live, defaults: defaults)
        // Should get .default config (possibly through migration that creates a default profile)
        #expect(config.provider == .foundationModels)
        #expect(config.model == "Apple Intelligence")
    }

    @Test func saveAndLoadProfiles() throws {
        let profiles = [
            LLMModelProfile(name: "Profile1", config: LLMConfig(provider: .ollama, model: "llama3")),
            LLMModelProfile(name: "Profile2", config: LLMConfig(provider: .openAI, model: "gpt-4")),
        ]
        LLMProfileStore.saveProfiles(profiles, defaults: defaults)
        let loaded = LLMProfileStore.loadProfiles(defaults: defaults)
        try #require(loaded.count == 2)
        #expect(loaded[0].name == "Profile1")
        #expect(loaded[1].name == "Profile2")
        #expect(loaded[0].config.provider == .ollama)
        #expect(loaded[1].config.provider == .openAI)
    }

    @Test func deleteProfileClearsRoleAssignment() {
        var profiles = [
            LLMModelProfile(name: "ToDelete", config: .default)
        ]
        LLMProfileStore.saveProfiles(profiles, defaults: defaults)
        let id = profiles[0].id
        LLMProfileStore.setAssignedProfileID(id, for: .live, defaults: defaults)

        LLMProfileStore.deleteProfile(id: id, from: &profiles, defaults: defaults)
        #expect(profiles.isEmpty)
        #expect(LLMProfileStore.assignedProfileID(for: .live, defaults: defaults) == nil)
    }
}
