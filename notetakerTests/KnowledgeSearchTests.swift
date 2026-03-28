import Foundation
import Testing
import SwiftData
@testable import notetaker

@Suite("KnowledgeSearchLogic")
struct KnowledgeSearchTests {

    // MARK: - extractKeywords

    @Test("extracts basic keywords from query")
    func extractKeywordsBasic() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "discuss budget meeting")
        #expect(keywords == ["discuss", "budget", "meeting"])
    }

    @Test("removes English stopwords")
    func extractKeywordsStopwords() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "what is the budget for this project")
        #expect(!keywords.contains("what"))
        #expect(!keywords.contains("is"))
        #expect(!keywords.contains("the"))
        #expect(!keywords.contains("for"))
        #expect(!keywords.contains("this"))
        #expect(keywords.contains("budget"))
        #expect(keywords.contains("project"))
    }

    @Test("removes Chinese stopwords")
    func extractKeywordsChineseStopwords() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "预算 的 了 项目")
        #expect(!keywords.contains("的"))
        #expect(!keywords.contains("了"))
        #expect(keywords.contains("预算"))
        #expect(keywords.contains("项目"))
    }

    @Test("lowercases and deduplicates")
    func extractKeywordsDedup() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "Budget budget BUDGET meeting")
        #expect(keywords == ["budget", "meeting"])
    }

    @Test("returns empty for empty query")
    func extractKeywordsEmpty() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "")
        #expect(keywords.isEmpty)
    }

    @Test("returns empty for stopwords-only query")
    func extractKeywordsOnlyStopwords() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "the a an is")
        #expect(keywords.isEmpty)
    }

    @Test("handles CJK characters by splitting into individual chars")
    func extractKeywordsCJK() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "讨论预算")
        // Should contain the whole word and individual chars
        #expect(keywords.contains("讨论预算"))
        #expect(keywords.contains("讨"))
        #expect(keywords.contains("论"))
        #expect(keywords.contains("预"))
        #expect(keywords.contains("算"))
    }

    @Test("handles mixed language query")
    func extractKeywordsMixed() {
        let keywords = KnowledgeSearchLogic.extractKeywords(from: "budget 预算 meeting")
        #expect(keywords.contains("budget"))
        #expect(keywords.contains("预算"))
        #expect(keywords.contains("meeting"))
    }

    // MARK: - relevanceScore

    @Test("scores zero when no keywords match")
    func relevanceScoreNoMatch() {
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "hello world",
            keywords: ["budget"],
            date: Date(),
            now: Date()
        )
        #expect(score == 0)
    }

    @Test("scores keywords matched times 2 plus recency bonus")
    func relevanceScoreSingleMatch() {
        let now = Date()
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "discuss the budget",
            keywords: ["budget"],
            date: now,
            now: now
        )
        // 1 match * 2.0 + 1.0 recency (within 7 days) = 3.0
        #expect(score == 3.0)
    }

    @Test("scores multiple keyword matches")
    func relevanceScoreMultiMatch() {
        let now = Date()
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "budget meeting about the project budget",
            keywords: ["budget", "meeting", "project"],
            date: now,
            now: now
        )
        // 3 matches * 2.0 + 1.0 recency = 7.0
        #expect(score == 7.0)
    }

    @Test("recency bonus within 7 days is 1.0")
    func relevanceScoreRecent() {
        let now = Date()
        let threeDaysAgo = now.addingTimeInterval(-3 * 86400)
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "budget",
            keywords: ["budget"],
            date: threeDaysAgo,
            now: now
        )
        #expect(score == 3.0) // 1 * 2.0 + 1.0
    }

    @Test("recency bonus within 30 days is 0.5")
    func relevanceScoreMediumRecency() {
        let now = Date()
        let fifteenDaysAgo = now.addingTimeInterval(-15 * 86400)
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "budget",
            keywords: ["budget"],
            date: fifteenDaysAgo,
            now: now
        )
        #expect(score == 2.5) // 1 * 2.0 + 0.5
    }

    @Test("recency bonus older than 30 days is 0.2")
    func relevanceScoreOldRecency() {
        let now = Date()
        let sixtyDaysAgo = now.addingTimeInterval(-60 * 86400)
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "budget",
            keywords: ["budget"],
            date: sixtyDaysAgo,
            now: now
        )
        #expect(score == 2.2) // 1 * 2.0 + 0.2
    }

    @Test("matching is case insensitive")
    func relevanceScoreCaseInsensitive() {
        let now = Date()
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "BUDGET Meeting",
            keywords: ["budget", "meeting"],
            date: now,
            now: now
        )
        #expect(score == 5.0) // 2 * 2.0 + 1.0
    }

    @Test("empty keywords returns zero")
    func relevanceScoreEmptyKeywords() {
        let score = KnowledgeSearchLogic.relevanceScore(
            text: "budget meeting",
            keywords: [],
            date: Date(),
            now: Date()
        )
        #expect(score == 0)
    }

    // MARK: - groupBySession

    @Test("groups snippets by session ID")
    func groupBySessionBasic() {
        let container = try! ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let session1 = RecordingSession(title: "Session 1", segments: [])
        let session2 = RecordingSession(title: "Session 2", segments: [])
        context.insert(session1)
        context.insert(session2)
        try! context.save()

        let snippets = [
            SearchSnippet(sessionID: session1.persistentModelID, sessionTitle: "Session 1", sessionDate: Date(), segmentText: "text 1", segmentStartTime: 0, score: 5.0),
            SearchSnippet(sessionID: session1.persistentModelID, sessionTitle: "Session 1", sessionDate: Date(), segmentText: "text 2", segmentStartTime: 30, score: 3.0),
            SearchSnippet(sessionID: session2.persistentModelID, sessionTitle: "Session 2", sessionDate: Date(), segmentText: "text 3", segmentStartTime: 0, score: 4.0),
        ]

        let groups = KnowledgeSearchLogic.groupBySession(snippets)
        #expect(groups.count == 2)
        // First group should have highest topScore
        #expect(groups[0].topScore == 5.0)
        #expect(groups[0].snippets.count == 2)
        #expect(groups[1].topScore == 4.0)
        #expect(groups[1].snippets.count == 1)
    }

    @Test("deduplicates overlapping segments within a session")
    func groupBySessionDedup() {
        let container = try! ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let session = RecordingSession(title: "Session", segments: [])
        context.insert(session)
        try! context.save()

        let snippets = [
            SearchSnippet(sessionID: session.persistentModelID, sessionTitle: "Session", sessionDate: Date(), segmentText: "same text", segmentStartTime: 0, score: 5.0),
            SearchSnippet(sessionID: session.persistentModelID, sessionTitle: "Session", sessionDate: Date(), segmentText: "same text", segmentStartTime: 0, score: 3.0),
            SearchSnippet(sessionID: session.persistentModelID, sessionTitle: "Session", sessionDate: Date(), segmentText: "different text", segmentStartTime: 30, score: 2.0),
        ]

        let groups = KnowledgeSearchLogic.groupBySession(snippets)
        #expect(groups.count == 1)
        #expect(groups[0].snippets.count == 2) // "same text" deduped, "different text" kept
    }

    @Test("sorts snippets within group by start time")
    func groupBySessionSortOrder() {
        let container = try! ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let session = RecordingSession(title: "Session", segments: [])
        context.insert(session)
        try! context.save()

        let snippets = [
            SearchSnippet(sessionID: session.persistentModelID, sessionTitle: "Session", sessionDate: Date(), segmentText: "later", segmentStartTime: 120, score: 3.0),
            SearchSnippet(sessionID: session.persistentModelID, sessionTitle: "Session", sessionDate: Date(), segmentText: "earlier", segmentStartTime: 10, score: 5.0),
        ]

        let groups = KnowledgeSearchLogic.groupBySession(snippets)
        #expect(groups[0].snippets[0].segmentText == "earlier")
        #expect(groups[0].snippets[1].segmentText == "later")
    }

    // MARK: - formatContext

    @Test("formats empty groups as empty string")
    func formatContextEmpty() {
        let result = KnowledgeSearchLogic.formatContext(groups: [])
        #expect(result == "")
    }

    @Test("formats groups with session headers and timestamps")
    func formatContextBasic() {
        let container = try! ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let session = RecordingSession(title: "Team Meeting", segments: [])
        context.insert(session)
        try! context.save()

        let snippets = [
            SearchSnippet(sessionID: session.persistentModelID, sessionTitle: "Team Meeting", sessionDate: Date(), segmentText: "discuss the budget", segmentStartTime: 65, score: 5.0),
        ]

        let groups = KnowledgeSearchLogic.groupBySession(snippets)
        let result = KnowledgeSearchLogic.formatContext(groups: groups)

        #expect(result.contains("## Team Meeting"))
        #expect(result.contains("[01:05] discuss the budget"))
    }

    @Test("truncates output at maxChars limit")
    func formatContextTruncation() {
        let container = try! ModelContainer(for: RecordingSession.self, TranscriptSegment.self, SummaryBlock.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let session = RecordingSession(title: "Long Session", segments: [])
        context.insert(session)
        try! context.save()

        var snippets: [SearchSnippet] = []
        for i in 0..<100 {
            snippets.append(SearchSnippet(
                sessionID: session.persistentModelID,
                sessionTitle: "Long Session",
                sessionDate: Date(),
                segmentText: "This is a fairly long segment text number \(i) with some additional content to fill space",
                segmentStartTime: TimeInterval(i * 30),
                score: Double(100 - i)
            ))
        }

        let groups = KnowledgeSearchLogic.groupBySession(snippets)
        let result = KnowledgeSearchLogic.formatContext(groups: groups, maxChars: 200)

        #expect(result.count <= 200)
    }

    // MARK: - PromptBuilder.buildSearchPrompt

    @Test("builds search prompt with system, context, and query messages")
    func buildSearchPromptBasic() {
        let messages = PromptBuilder.buildSearchPrompt(
            query: "What was discussed about the budget?",
            context: "## Meeting\n[01:05] We discussed the budget allocation",
            language: "auto"
        )

        #expect(messages.count == 3)
        #expect(messages[0].role == .system)
        #expect(messages[0].cacheHint == true)
        #expect(messages[1].role == .user)
        #expect(messages[1].content.contains("Transcript excerpts"))
        #expect(messages[1].cacheHint == true)
        #expect(messages[2].role == .user)
        #expect(messages[2].content == "What was discussed about the budget?")
    }

    @Test("includes language instruction when not auto")
    func buildSearchPromptLanguage() {
        let messages = PromptBuilder.buildSearchPrompt(
            query: "test query",
            context: "some context",
            language: "Chinese"
        )

        #expect(messages[0].content.contains("Chinese"))
    }

    @Test("omits context message when empty")
    func buildSearchPromptNoContext() {
        let messages = PromptBuilder.buildSearchPrompt(
            query: "test query",
            context: "",
            language: "auto"
        )

        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
        #expect(messages[1].content == "test query")
    }
}
