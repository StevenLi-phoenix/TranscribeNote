import Foundation
import SwiftData
import os

extension ModelContext {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TranscribeNote", category: "ModelContext")

    /// Save with error logging instead of silently swallowing failures.
    func saveQuietly() {
        do {
            try save()
        } catch {
            Self.logger.error("ModelContext save failed: \(error.localizedDescription)")
        }
    }
}
