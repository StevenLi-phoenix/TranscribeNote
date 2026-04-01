import Foundation
import os

/// A named LLM model configuration profile.
/// Profiles are stored as a JSON array in UserDefaults; API keys in Keychain.
nonisolated struct LLMModelProfile: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var name: String
    var config: LLMConfig
    /// When the last connection test was run. nil = never tested.
    var lastTestedAt: Date? = nil
    /// Result of the last connection test. nil = never tested.
    var lastTestPassed: Bool? = nil
    /// Cumulative input tokens used across all LLM calls (prompts).
    var totalInputTokens: Int = 0
    /// Cumulative output tokens generated across all LLM calls (completions).
    var totalOutputTokens: Int = 0
    /// Total number of successful LLM requests made with this profile.
    var totalRequests: Int = 0

    init(id: UUID = UUID(), name: String, config: LLMConfig = .default) {
        self.id = id
        self.name = name
        self.config = config
    }

    /// Keychain account name for this profile's API key.
    var keychainKey: String { "notetaker.profile.\(id.uuidString).apiKey" }
}

/// Which LLM role a profile is assigned to.
nonisolated enum LLMRole: String, CaseIterable, Sendable {
    case live
    case overall
    case title
    case chat
    case actionItems

    var displayName: String {
        switch self {
        case .live: "Live Summarization"
        case .overall: "Overall Summary"
        case .title: "Title Generation"
        case .chat: "Chat Q&A"
        case .actionItems: "Action Items"
        }
    }

    var subtitle: String {
        switch self {
        case .live: "Periodic summarization during recording"
        case .overall: "Post-recording complete summary"
        case .title: "Auto-generate session titles after recording"
        case .chat: "Ask questions about transcripts"
        case .actionItems: "Extract action items from transcripts"
        }
    }

    /// UserDefaults key for the assigned profile ID.
    var profileIDKey: String { "\(rawValue)LLMProfileID" }

    /// UserDefaults key for the "inherits live" toggle.
    var inheritsLiveKey: String { "\(rawValue)LLMInheritsLive" }
}

/// Centralized store for LLM model profiles and role assignments.
enum LLMProfileStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "LLMProfileStore")
    private static let profilesKey = "llmModelProfilesJSON"

    // MARK: - Profile CRUD

    static func loadProfiles(defaults: UserDefaults = .standard) -> [LLMModelProfile] {
        guard let json = defaults.string(forKey: profilesKey),
              let data = json.data(using: .utf8),
              var profiles = try? JSONDecoder().decode([LLMModelProfile].self, from: data) else {
            return migrateFromLegacy(defaults: defaults)
        }
        // Hydrate API keys from Keychain
        for i in profiles.indices {
            profiles[i].config.apiKey = KeychainService.load(key: profiles[i].keychainKey) ?? ""
        }
        return profiles
    }

    static func saveProfiles(_ profiles: [LLMModelProfile], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profiles),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Failed to encode LLM profiles")
            return
        }
        defaults.set(json, forKey: profilesKey)
        // Save each API key to Keychain (delete entry if empty to avoid storing blank secrets)
        for profile in profiles {
            if profile.config.apiKey.isEmpty {
                KeychainService.delete(key: profile.keychainKey)
            } else {
                KeychainService.save(key: profile.keychainKey, value: profile.config.apiKey)
            }
        }
        logger.debug("Saved \(profiles.count) LLM profiles")
    }

    static func deleteProfile(id: UUID, from profiles: inout [LLMModelProfile], defaults: UserDefaults = .standard) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            let profile = profiles.remove(at: index)
            KeychainService.delete(key: profile.keychainKey)
            // Clear any role assignments pointing to this profile
            for role in LLMRole.allCases {
                if assignedProfileID(for: role, defaults: defaults) == id {
                    defaults.removeObject(forKey: role.profileIDKey)
                }
            }
            saveProfiles(profiles, defaults: defaults)
            logger.info("Deleted profile '\(profile.name)' (\(id))")
        }
    }

    // MARK: - Usage & Test Recording

    /// Persist the result of a connection test for a profile.
    static func recordTestResult(profileID: UUID, passed: Bool, defaults: UserDefaults = .standard) {
        var profiles = loadProfiles(defaults: defaults)
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].lastTestedAt = Date()
        profiles[index].lastTestPassed = passed
        saveProfiles(profiles, defaults: defaults)
        logger.debug("Recorded test result for profile \(profileID): \(passed ? "passed" : "failed")")
    }

    /// Accumulate token usage for whichever profile matches the given config.
    /// Matches on provider + model + baseURL. No-op if no match found.
    static func recordUsageForConfig(_ config: LLMConfig, inputTokens: Int, outputTokens: Int, defaults: UserDefaults = .standard) {
        var profiles = loadProfiles(defaults: defaults)
        guard let index = profiles.firstIndex(where: {
            $0.config.provider == config.provider &&
            $0.config.model == config.model &&
            $0.config.baseURL == config.baseURL
        }) else { return }
        profiles[index].totalInputTokens += inputTokens
        profiles[index].totalOutputTokens += outputTokens
        profiles[index].totalRequests += 1
        saveProfiles(profiles, defaults: defaults)
    }

    // MARK: - Role Assignment

    static func assignedProfileID(for role: LLMRole, defaults: UserDefaults = .standard) -> UUID? {
        guard let str = defaults.string(forKey: role.profileIDKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func setAssignedProfileID(_ id: UUID?, for role: LLMRole, defaults: UserDefaults = .standard) {
        if let id {
            defaults.set(id.uuidString, forKey: role.profileIDKey)
        } else {
            defaults.removeObject(forKey: role.profileIDKey)
        }
    }

    static func inheritsLive(for role: LLMRole, defaults: UserDefaults = .standard) -> Bool {
        guard role != .live else { return false }
        return defaults.bool(forKey: role.inheritsLiveKey)
    }

    static func setInheritsLive(_ value: Bool, for role: LLMRole, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: role.inheritsLiveKey)
    }

    // MARK: - Config Resolution

    /// Resolve the effective LLMConfig for a given role.
    static func resolveConfig(for role: LLMRole, defaults: UserDefaults = .standard) -> LLMConfig {
        let profiles = loadProfiles(defaults: defaults)

        // If this role inherits live, resolve live instead
        if role != .live && inheritsLive(for: role, defaults: defaults) {
            return resolveConfigFromProfiles(role: .live, profiles: profiles, defaults: defaults)
        }

        return resolveConfigFromProfiles(role: role, profiles: profiles, defaults: defaults)
    }

    private static func resolveConfigFromProfiles(role: LLMRole, profiles: [LLMModelProfile], defaults: UserDefaults = .standard) -> LLMConfig {
        // Try assigned profile ID
        if let profileID = assignedProfileID(for: role, defaults: defaults),
           let profile = profiles.first(where: { $0.id == profileID }) {
            return profile.config
        }
        // Fallback: first profile if available
        if let first = profiles.first {
            return first.config
        }
        // Legacy fallback
        return legacyFallbackConfig(for: role, defaults: defaults)
    }

    /// Fallback to legacy UserDefaults keys for backward compatibility.
    private static func legacyFallbackConfig(for role: LLMRole, defaults: UserDefaults = .standard) -> LLMConfig {
        let keys: [String]
        switch role {
        case .live: keys = ["liveLLMConfigJSON", "llmConfigJSON"]
        case .overall: keys = ["overallLLMConfigJSON", "liveLLMConfigJSON", "llmConfigJSON"]
        case .title: keys = ["titleLLMConfigJSON", "liveLLMConfigJSON", "llmConfigJSON"]
        case .chat: keys = ["liveLLMConfigJSON", "llmConfigJSON"]
        case .actionItems: keys = ["liveLLMConfigJSON", "llmConfigJSON"]
        }
        for key in keys {
            if let json = defaults.string(forKey: key), !json.isEmpty {
                return LLMConfig.fromUserDefaults(key: key, defaults: defaults)
            }
        }
        return .default
    }

    // MARK: - Migration

    /// Migrate legacy per-role configs into profiles on first launch.
    private static func migrateFromLegacy(defaults: UserDefaults = .standard) -> [LLMModelProfile] {
        logger.info("No profiles found, migrating from legacy configs")
        var profiles: [LLMModelProfile] = []
        var seen = Set<String>() // Deduplicate by provider+model+baseURL

        let legacyKeys: [(key: String, role: LLMRole, name: String)] = [
            ("liveLLMConfigJSON", .live, "Live"),
            ("overallLLMConfigJSON", .overall, "Overall"),
            ("titleLLMConfigJSON", .title, "Title"),
            ("llmConfigJSON", .live, "Default"),
        ]

        for (key, role, fallbackName) in legacyKeys {
            guard let json = defaults.string(forKey: key), !json.isEmpty else { continue }
            var config = LLMConfig.fromUserDefaults(key: key, defaults: defaults)
            let dedup = "\(config.provider.rawValue)|\(config.model)|\(config.baseURL)"
            guard !seen.contains(dedup) else { continue }
            seen.insert(dedup)

            let name = config.model.isEmpty ? fallbackName : config.model
            let profile = LLMModelProfile(name: name, config: config)
            profiles.append(profile)

            // Assign this profile to the role it came from
            setAssignedProfileID(profile.id, for: role, defaults: defaults)
        }

        if profiles.isEmpty {
            let defaultProfile = LLMModelProfile(name: "Default", config: .default)
            profiles.append(defaultProfile)
            setAssignedProfileID(defaultProfile.id, for: .live, defaults: defaults)
        }

        saveProfiles(profiles, defaults: defaults)
        logger.info("Migrated \(profiles.count) legacy configs into profiles")
        return profiles
    }
}
