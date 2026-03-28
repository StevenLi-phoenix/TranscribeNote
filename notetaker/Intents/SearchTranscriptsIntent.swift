import AppIntents
import SwiftData
import os

struct SearchTranscriptsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Transcripts"
    static var description = IntentDescription("Search across all recording transcripts")

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SearchTranscriptsIntent")

    @Parameter(title: "Search Query")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[SessionEntity]> & ProvidesDialog {
        Self.logger.info("SearchTranscriptsIntent triggered, query='\(query)'")
        try AppIntentState.shared.ensureReady()
        guard let container = AppIntentState.shared.modelContainerRef else {
            throw AppIntentError.appNotRunning
        }

        let context = container.mainContext
        let searchQuery = query

        // Search transcript segments
        let segmentPredicate = #Predicate<TranscriptSegment> {
            $0.text.localizedStandardContains(searchQuery)
        }
        let segments = try context.fetch(FetchDescriptor(predicate: segmentPredicate))

        // Collect unique sessions
        var sessionIDs = Set<UUID>()
        var sessions: [RecordingSession] = []
        for segment in segments {
            if let session = segment.session, !sessionIDs.contains(session.id) {
                sessionIDs.insert(session.id)
                sessions.append(session)
            }
        }

        // Sort by date descending
        sessions.sort { $0.startedAt > $1.startedAt }

        let entities = sessions.prefix(10).map { session in
            SessionEntity(
                id: session.id.uuidString,
                title: session.title,
                date: session.startedAt,
                segmentCount: session.segments.count
            )
        }

        Self.logger.info("Search found \(sessions.count) session(s) for query '\(query)'")
        return .result(
            value: Array(entities),
            dialog: "Found \(sessions.count) session(s) matching \"\(query)\""
        )
    }
}
