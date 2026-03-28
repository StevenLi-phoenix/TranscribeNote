import AppIntents
import SwiftData
import os

struct GetLastSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Meeting Summary"
    static var description = IntentDescription("Get the summary of a recording session")

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "GetLastSummaryIntent")

    @Parameter(title: "Session")
    var session: SessionEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        Self.logger.info("GetLastSummaryIntent triggered")
        try AppIntentState.shared.ensureReady()
        guard let container = AppIntentState.shared.modelContainerRef else {
            throw AppIntentError.appNotRunning
        }

        let context = container.mainContext
        let targetSession: RecordingSession

        if let sessionEntity = session, let uuid = UUID(uuidString: sessionEntity.id) {
            let predicate = #Predicate<RecordingSession> { $0.id == uuid }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.fetchLimit = 1
            guard let found = try context.fetch(descriptor).first else {
                throw AppIntentError.noSessionFound
            }
            targetSession = found
        } else {
            // Get most recent session
            var descriptor = FetchDescriptor<RecordingSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            guard let last = try context.fetch(descriptor).first else {
                throw AppIntentError.noSessionFound
            }
            targetSession = last
        }

        // Find overall summary
        let sessionID = targetSession.id
        let summaryPredicate = #Predicate<SummaryBlock> {
            $0.session?.id == sessionID && $0.isOverall == true
        }
        let summaryDescriptor = FetchDescriptor(predicate: summaryPredicate)
        let summaries = try context.fetch(summaryDescriptor)

        if let summary = summaries.first {
            let content = summary.displayContent
            Self.logger.info("Returning summary for session '\(targetSession.title)'")
            return .result(
                value: content,
                dialog: "\(targetSession.title): \(String(content.prefix(200)))"
            )
        } else {
            Self.logger.info("No summary found for session '\(targetSession.title)'")
            return .result(
                value: "No summary available for this session.",
                dialog: "No summary found for \(targetSession.title)"
            )
        }
    }
}
