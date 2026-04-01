import Foundation
import os

nonisolated enum KeychainService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TranscribeNote", category: "Keychain")

    private static var serviceName: String {
        Bundle.main.bundleIdentifier ?? "com.transcribenote"
    }

    /// Save a string value to the Keychain. Overwrites if key already exists.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to encode value for key: \(key)")
            return false
        }

        // Delete existing item first (ignore result — may not exist)
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed for key '\(key)': OSStatus \(status)")
        } else {
            logger.debug("Keychain saved key '\(key)'")
        }
        return status == errSecSuccess
    }

    /// Load a string value from the Keychain. Returns nil if not found.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain load failed for key '\(key)': OSStatus \(status)")
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed for key '\(key)': OSStatus \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
