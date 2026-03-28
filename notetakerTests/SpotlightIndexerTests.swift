import Testing
import CoreSpotlight
import Foundation
@testable import notetaker

@Suite("SpotlightIndexer")
struct SpotlightIndexerTests {

    // MARK: - SpotlightSessionData

    @Test
    func sessionDataInit() {
        let id = UUID()
        let date = Date()
        let data = SpotlightSessionData(
            id: id,
            title: "Test Session",
            transcriptExcerpt: "Hello world",
            summaryExcerpt: "A summary",
            createdAt: date
        )
        #expect(data.id == id)
        #expect(data.title == "Test Session")
        #expect(data.transcriptExcerpt == "Hello world")
        #expect(data.summaryExcerpt == "A summary")
        #expect(data.createdAt == date)
    }

    // MARK: - sessionID(from:)

    @Test
    func sessionIDFromUserActivity() {
        let id = UUID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: id.uuidString]

        let parsed = SpotlightIndexer.sessionID(from: activity)
        #expect(parsed == id)
    }

    @Test
    func sessionIDFromUserActivityMissingIdentifier() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [:]

        let parsed = SpotlightIndexer.sessionID(from: activity)
        #expect(parsed == nil)
    }

    @Test
    func sessionIDFromUserActivityNilUserInfo() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)

        let parsed = SpotlightIndexer.sessionID(from: activity)
        #expect(parsed == nil)
    }

    @Test
    func sessionIDFromUserActivityInvalidUUID() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "not-a-uuid"]

        let parsed = SpotlightIndexer.sessionID(from: activity)
        #expect(parsed == nil)
    }

    // MARK: - Index / Deindex smoke tests (real CSSearchableIndex)

    @Test
    func indexSessionDoesNotThrow() async {
        let indexer = SpotlightIndexer()
        let data = SpotlightSessionData(
            id: UUID(),
            title: "Smoke Test",
            transcriptExcerpt: "transcript text",
            summaryExcerpt: "summary text",
            createdAt: Date()
        )
        // Should complete without error
        await indexer.indexSession(data)
    }

    @Test
    func deindexSessionDoesNotThrow() async {
        let indexer = SpotlightIndexer()
        // Deindexing a nonexistent ID should not throw
        await indexer.deindexSession(id: UUID())
    }

    @Test
    func deindexSessionsDoesNotThrow() async {
        let indexer = SpotlightIndexer()
        await indexer.deindexSessions(ids: [UUID(), UUID()])
    }

    @Test
    func reindexAllDoesNotThrow() async {
        let indexer = SpotlightIndexer()
        let sessions = [
            SpotlightSessionData(id: UUID(), title: "A", transcriptExcerpt: "a", summaryExcerpt: "", createdAt: Date()),
            SpotlightSessionData(id: UUID(), title: "B", transcriptExcerpt: "b", summaryExcerpt: "s", createdAt: Date()),
        ]
        await indexer.reindexAll(sessions: sessions)
    }

    @Test
    func reindexAllEmptyDoesNotThrow() async {
        let indexer = SpotlightIndexer()
        await indexer.reindexAll(sessions: [])
    }

    @Test
    func deleteAllIndexesDoesNotThrow() async {
        let indexer = SpotlightIndexer()
        await indexer.deleteAllIndexes()
    }

    // MARK: - sessionData(from:) with SwiftData

    @MainActor @Test
    func sessionDataFromRecordingSession() {
        let session = RecordingSession(
            startedAt: Date(timeIntervalSince1970: 1000),
            title: "My Recording"
        )
        let seg1 = TranscriptSegment(startTime: 0, endTime: 5, text: "Hello")
        let seg2 = TranscriptSegment(startTime: 5, endTime: 10, text: "World")
        seg1.session = session
        seg2.session = session
        session.segments = [seg1, seg2]

        let summary = SummaryBlock(coveringFrom: 0, coveringTo: 10, content: "Overall notes", isOverall: true)
        summary.session = session
        session.summaries = [summary]

        let data = SpotlightIndexer.sessionData(from: session)
        #expect(data.id == session.id)
        #expect(data.title == "My Recording")
        #expect(data.transcriptExcerpt == "Hello World")
        #expect(data.summaryExcerpt == "Overall notes")
        #expect(data.createdAt == session.startedAt)
    }

    @MainActor @Test
    func sessionDataTruncatesTranscriptAt500Chars() {
        let session = RecordingSession(title: "Long")
        let longText = String(repeating: "A", count: 600)
        let seg = TranscriptSegment(startTime: 0, endTime: 1, text: longText)
        seg.session = session
        session.segments = [seg]

        let data = SpotlightIndexer.sessionData(from: session)
        #expect(data.transcriptExcerpt.count == 500)
    }

    @MainActor @Test
    func sessionDataTruncatesSummaryAt300Chars() {
        let session = RecordingSession(title: "Long Summary")
        let longSummary = String(repeating: "B", count: 400)
        let summary = SummaryBlock(coveringFrom: 0, coveringTo: 1, content: longSummary, isOverall: true)
        summary.session = session
        session.summaries = [summary]

        let data = SpotlightIndexer.sessionData(from: session)
        #expect(data.summaryExcerpt.count == 300)
    }

    @MainActor @Test
    func sessionDataEmptySegmentsAndSummaries() {
        let session = RecordingSession(title: "Empty")

        let data = SpotlightIndexer.sessionData(from: session)
        #expect(data.transcriptExcerpt.isEmpty)
        #expect(data.summaryExcerpt.isEmpty)
    }

    @MainActor @Test
    func sessionDataIgnoresNonOverallSummaries() {
        let session = RecordingSession(title: "Chunks Only")
        let chunk = SummaryBlock(coveringFrom: 0, coveringTo: 5, content: "Chunk content", isOverall: false)
        chunk.session = session
        session.summaries = [chunk]

        let data = SpotlightIndexer.sessionData(from: session)
        #expect(data.summaryExcerpt.isEmpty)
    }

    // MARK: - Domain identifier

    @Test
    func domainIdentifierIsExpected() {
        #expect(SpotlightIndexer.domainIdentifier == "com.notetaker.session")
    }
}
