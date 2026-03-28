import CoreSpotlight
import UniformTypeIdentifiers
import os

/// Lightweight data carrier for passing session info across isolation boundaries.
nonisolated struct SpotlightSessionData: Sendable {
    let id: UUID
    let title: String
    let transcriptExcerpt: String
    let summaryExcerpt: String
    let createdAt: Date
}

/// Indexes recording sessions into macOS Spotlight for system-wide search.
nonisolated final class SpotlightIndexer: @unchecked Sendable {
    static let shared = SpotlightIndexer()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "SpotlightIndexer"
    )
    static let domainIdentifier = "com.notetaker.session"

    private let searchableIndex: CSSearchableIndex

    init(searchableIndex: CSSearchableIndex = .default()) {
        self.searchableIndex = searchableIndex
    }

    // MARK: - Public API

    /// Index a single session into Spotlight.
    func indexSession(_ data: SpotlightSessionData) async {
        let item = makeSearchableItem(from: data)
        do {
            try await searchableIndex.indexSearchableItems([item])
            Self.logger.info("Indexed session \(data.id) into Spotlight")
        } catch {
            Self.logger.error("Failed to index session \(data.id): \(error.localizedDescription)")
        }
    }

    /// Remove a session from Spotlight by ID.
    func deindexSession(id: UUID) async {
        do {
            try await searchableIndex.deleteSearchableItems(withIdentifiers: [id.uuidString])
            Self.logger.info("Deindexed session \(id) from Spotlight")
        } catch {
            Self.logger.error("Failed to deindex session \(id): \(error.localizedDescription)")
        }
    }

    /// Remove multiple sessions from Spotlight by IDs.
    func deindexSessions(ids: Set<UUID>) async {
        let identifiers = ids.map(\.uuidString)
        do {
            try await searchableIndex.deleteSearchableItems(withIdentifiers: identifiers)
            Self.logger.info("Deindexed \(ids.count) session(s) from Spotlight")
        } catch {
            Self.logger.error("Failed to deindex \(ids.count) session(s): \(error.localizedDescription)")
        }
    }

    /// Batch reindex all sessions — deletes existing indexes first.
    func reindexAll(sessions: [SpotlightSessionData]) async {
        Self.logger.info("Reindexing \(sessions.count) session(s) in Spotlight")
        do {
            try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
        } catch {
            Self.logger.error("Failed to clear existing Spotlight index: \(error.localizedDescription)")
        }

        guard !sessions.isEmpty else { return }

        let items = sessions.map { makeSearchableItem(from: $0) }
        do {
            try await searchableIndex.indexSearchableItems(items)
            Self.logger.info("Reindexed \(sessions.count) session(s) into Spotlight")
        } catch {
            Self.logger.error("Failed to reindex sessions: \(error.localizedDescription)")
        }
    }

    /// Clear all Spotlight indexes for this app domain.
    func deleteAllIndexes() async {
        do {
            try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
            Self.logger.info("Cleared all Spotlight indexes")
        } catch {
            Self.logger.error("Failed to clear Spotlight indexes: \(error.localizedDescription)")
        }
    }

    // MARK: - Static Helpers

    /// Build `SpotlightSessionData` from a `RecordingSession` model object.
    /// Must be called on the MainActor (RecordingSession is a SwiftData @Model).
    @MainActor
    static func sessionData(from session: RecordingSession) -> SpotlightSessionData {
        let transcriptExcerpt = session.segments
            .sorted { $0.startTime < $1.startTime }
            .map(\.text)
            .joined(separator: " ")
            .prefix(500)

        let summaryExcerpt = session.summaries
            .filter { $0.isOverall }
            .first
            .map(\.displayContent)
            .map { String($0.prefix(300)) } ?? ""

        return SpotlightSessionData(
            id: session.id,
            title: session.title,
            transcriptExcerpt: String(transcriptExcerpt),
            summaryExcerpt: summaryExcerpt,
            createdAt: session.startedAt
        )
    }

    /// Parse a session UUID from an `NSUserActivity` triggered by Spotlight.
    static func sessionID(from userActivity: NSUserActivity) -> UUID? {
        guard let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return nil
        }
        return UUID(uuidString: identifier)
    }

    // MARK: - Private

    private func makeSearchableItem(from data: SpotlightSessionData) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = data.title.isEmpty ? "Recording" : data.title
        attributes.contentDescription = buildContentDescription(
            transcript: data.transcriptExcerpt,
            summary: data.summaryExcerpt
        )
        attributes.keywords = buildKeywords(from: data.title)
        attributes.timestamp = data.createdAt

        return CSSearchableItem(
            uniqueIdentifier: data.id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
    }

    private func buildContentDescription(transcript: String, summary: String) -> String {
        var parts: [String] = []
        if !transcript.isEmpty {
            parts.append(transcript)
        }
        if !summary.isEmpty {
            parts.append(summary)
        }
        return parts.joined(separator: "\n\n")
    }

    private func buildKeywords(from title: String) -> [String] {
        guard !title.isEmpty else { return [] }
        return title.split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 }
    }
}
