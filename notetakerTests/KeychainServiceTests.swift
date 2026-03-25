import Testing
import Foundation
@testable import notetaker

@Suite("KeychainService", .serialized)
struct KeychainServiceTests {

    private func cleanup(_ key: String) {
        _ = KeychainService.delete(key: key)
    }

    @Test
    func saveAndLoad() {
        let key = "test.keychain.saveAndLoad"
        defer { cleanup(key) }

        let saved = KeychainService.save(key: key, value: "my-secret-key")
        #expect(saved)

        let loaded = KeychainService.load(key: key)
        #expect(loaded == "my-secret-key")
    }

    @Test
    func loadNonexistent() {
        let loaded = KeychainService.load(key: "test.keychain.nonexistent.\(UUID().uuidString)")
        #expect(loaded == nil)
    }

    @Test
    func deleteExisting() {
        let key = "test.keychain.delete"
        defer { cleanup(key) }

        _ = KeychainService.save(key: key, value: "to-delete")
        let deleted = KeychainService.delete(key: key)
        #expect(deleted)
        #expect(KeychainService.load(key: key) == nil)
    }

    @Test
    func overwrite() {
        let key = "test.keychain.overwrite"
        defer { cleanup(key) }

        _ = KeychainService.save(key: key, value: "original")
        let overwritten = KeychainService.save(key: key, value: "updated")
        #expect(overwritten)
        #expect(KeychainService.load(key: key) == "updated")
    }

    @Test
    func emptyString() {
        let key = "test.keychain.empty"
        defer { cleanup(key) }

        let saved = KeychainService.save(key: key, value: "")
        #expect(saved)
        #expect(KeychainService.load(key: key) == "")
    }
}
