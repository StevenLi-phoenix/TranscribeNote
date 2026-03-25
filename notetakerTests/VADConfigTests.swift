import Testing
import Foundation
@testable import notetaker

@Suite("VADConfig Tests")
struct VADConfigTests {

    @Test("Default config has expected values")
    func defaultValues() {
        let config = VADConfig.default
        #expect(config.vadEnabled == true)
        #expect(config.silenceThreshold == 0.05)
        #expect(config.silenceTimeoutSeconds == 300)
    }

    @Test("Encodes and decodes round-trip")
    func encodeDecode() throws {
        let config = VADConfig(
            vadEnabled: false,
            silenceThreshold: 0.10,
            silenceTimeoutSeconds: 60
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VADConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test("Decodes with missing keys using defaults")
    func decodesWithDefaults() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(VADConfig.self, from: data)
        #expect(config.vadEnabled == true)
        #expect(config.silenceThreshold == 0.05)
        #expect(config.silenceTimeoutSeconds == 300)
    }

    @Test("Nil timeout encodes and decodes correctly")
    func nilTimeout() throws {
        let config = VADConfig(
            vadEnabled: true,
            silenceThreshold: 0.05,
            silenceTimeoutSeconds: nil
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VADConfig.self, from: data)
        #expect(decoded.silenceTimeoutSeconds == nil)
    }

    @Test("fromUserDefaults returns default for missing key")
    func fromUserDefaultsMissing() {
        let config = VADConfig.fromUserDefaults(key: "nonExistentVADKey_\(UUID().uuidString)")
        #expect(config == .default)
    }

    @Test("fromUserDefaults loads stored config")
    func fromUserDefaultsStored() throws {
        let key = "testVADConfig_\(UUID().uuidString)"
        let config = VADConfig(vadEnabled: false, silenceThreshold: 0.15, silenceTimeoutSeconds: 60)
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(String(data: data, encoding: .utf8), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let loaded = VADConfig.fromUserDefaults(key: key)
        #expect(loaded == config)
    }
}
