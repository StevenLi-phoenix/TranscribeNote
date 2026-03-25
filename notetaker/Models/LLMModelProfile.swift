import Foundation
import os

/// A named LLM model configuration profile.
/// Profiles are stored as a JSON array in UserDefaults; API keys in Keychain.
nonisolated struct LLMModelProfile: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var name: String
    var config: LLMConfig

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

    var displayName: String {
        switch self {
        case .live: "Live Summarization"
        case .overall: "Overall Summary"
        case .title: "Title Generation"
        }
    }

    var subtitle: String {
        switch self {
        case .live: "Periodic summarization during recording"
        case .overall: "Post-recording complete summary"
        case .title: "Auto-generate session titles after recording"
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

    static func loadProfiles() -> [LLMModelProfile] {
        guard let json = UserDefaults.standard.string(forKey: profilesKey),
              let data = json.data(using: .utf8),
              var profiles = try? JSONDecoder().decode([LLMModelProfile].self, from: data) else {
            return migrateFromLegacy()
        }
        // Hydrate API keys from Keychain
        for i in profiles.indices {
            profiles[i].config.apiKey = KeychainService.load(key: profiles[i].keychainKey) ?? ""
        }
        return profiles
    }

    static func saveProfiles(_ profiles: [LLMModelProfile]) {
        guard let data = try? JSONEncoder().encode(profiles),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Failed to encode LLM profiles")
            return
        }
        UserDefaults.standard.set(json, forKey: profilesKey)
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

    static func deleteProfile(id: UUID, from profiles: inout [LLMModelProfile]) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            let profile = profiles.remove(at: index)
            KeychainService.delete(key: profile.keychainKey)
            // Clear any role assignments pointing to this profile
            for role in LLMRole.allCases {
                if assignedProfileID(for: role) == id {
                    UserDefaults.standard.removeObject(forKey: role.profileIDKey)
                }
            }
            saveProfiles(profiles)
            logger.info("Deleted profile '\(profile.name)' (\(id))")
        }
    }

    // MARK: - Role Assignment

    static func assignedProfileID(for role: LLMRole) -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: role.profileIDKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func setAssignedProfileID(_ id: UUID?, for role: LLMRole) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: role.profileIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: role.profileIDKey)
        }
    }

    static func inheritsLive(for role: LLMRole) -> Bool {
        guard role != .live else { return false }
        return UserDefaults.standard.bool(forKey: role.inheritsLiveKey)
    }

    static func setInheritsLive(_ value: Bool, for role: LLMRole) {
        UserDefaults.standard.set(value, forKey: role.inheritsLiveKey)
    }

    // MARK: - Config Resolution

    /// Resolve the effective LLMConfig for a given role.
    static func resolveConfig(for role: LLMRole) -> LLMConfig {
        let profiles = loadProfiles()

        // If this role inherits live, resolve live instead
        if role != .live && inheritsLive(for: role) {
            return resolveConfigFromProfiles(role: .live, profiles: profiles)
        }

        return resolveConfigFromProfiles(role: role, profiles: profiles)
    }

    private static func resolveConfigFromProfiles(role: LLMRole, profiles: [LLMModelProfile]) -> LLMConfig {
        // Try assigned profile ID
        if let profileID = assignedProfileID(for: role),
           let profile = profiles.first(where: { $0.id == profileID }) {
            return profile.config
        }
        // Fallback: first profile if available
        if let first = profiles.first {
            return first.config
        }
        // Legacy fallback
        return legacyFallbackConfig(for: role)
    }

    /// Fallback to legacy UserDefaults keys for backward compatibility.
    private static func legacyFallbackConfig(for role: LLMRole) -> LLMConfig {
        let keys: [String]
        switch role {
        case .live: keys = ["liveLLMConfigJSON", "llmConfigJSON"]
        case .overall: keys = ["overallLLMConfigJSON", "liveLLMConfigJSON", "llmConfigJSON"]
        case .title: keys = ["titleLLMConfigJSON", "liveLLMConfigJSON", "llmConfigJSON"]
        }
        for key in keys {
            if let json = UserDefaults.standard.string(forKey: key), !json.isEmpty {
                return LLMConfig.fromUserDefaults(key: key)
            }
        }
        return .default
    }

    // MARK: - Migration

    /// Migrate legacy per-role configs into profiles on first launch.
    private static func migrateFromLegacy() -> [LLMModelProfile] {
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
            guard let json = UserDefaults.standard.string(forKey: key), !json.isEmpty else { continue }
            var config = LLMConfig.fromUserDefaults(key: key)
            let dedup = "\(config.provider.rawValue)|\(config.model)|\(config.baseURL)"
            guard !seen.contains(dedup) else { continue }
            seen.insert(dedup)

            let name = config.model.isEmpty ? fallbackName : config.model
            let profile = LLMModelProfile(name: name, config: config)
            profiles.append(profile)

            // Assign this profile to the role it came from
            setAssignedProfileID(profile.id, for: role)
        }

        if profiles.isEmpty {
            let defaultProfile = LLMModelProfile(name: "Default", config: .default)
            profiles.append(defaultProfile)
            setAssignedProfileID(defaultProfile.id, for: .live)
        }

        saveProfiles(profiles)
        logger.info("Migrated \(profiles.count) legacy configs into profiles")
        return profiles
    }
}
