import Foundation

nonisolated struct VADConfig: Codable, Sendable, Equatable {
    var vadEnabled: Bool
    var silenceThreshold: Float
    var silenceTimeoutSeconds: Int?

    private enum CodingKeys: String, CodingKey {
        case vadEnabled, silenceThreshold, silenceTimeoutSeconds
    }

    static let `default` = VADConfig(
        vadEnabled: true,
        silenceThreshold: 0.05,
        silenceTimeoutSeconds: 300
    )

    init(
        vadEnabled: Bool = true,
        silenceThreshold: Float = 0.05,
        silenceTimeoutSeconds: Int? = 300
    ) {
        self.vadEnabled = vadEnabled
        self.silenceThreshold = silenceThreshold
        self.silenceTimeoutSeconds = silenceTimeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vadEnabled = try container.decodeIfPresent(Bool.self, forKey: .vadEnabled) ?? true
        silenceThreshold = try container.decodeIfPresent(Float.self, forKey: .silenceThreshold) ?? 0.05
        // Use default 300 only when the key is absent; explicit null → nil
        if container.contains(.silenceTimeoutSeconds) {
            silenceTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .silenceTimeoutSeconds)
        } else {
            silenceTimeoutSeconds = 300
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vadEnabled, forKey: .vadEnabled)
        try container.encode(silenceThreshold, forKey: .silenceThreshold)
        // Always write the key so nil round-trips as null (not "key absent")
        try container.encode(silenceTimeoutSeconds, forKey: .silenceTimeoutSeconds)
    }

    /// Load from UserDefaults, falling back to `.default`.
    static func fromUserDefaults(key: String = "vadConfigJSON", defaults: UserDefaults = .standard) -> VADConfig {
        guard let json = defaults.string(forKey: key),
              let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(VADConfig.self, from: data) else {
            return .default
        }
        return config
    }
}
