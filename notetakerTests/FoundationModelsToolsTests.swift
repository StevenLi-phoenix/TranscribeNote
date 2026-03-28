import Foundation
import Testing
@testable import notetaker

@Suite("FoundationModelsTools Tests")
struct FoundationModelsToolsTests {

    // MARK: - SessionSearchLogic.findMatchingSegments

    @Test("finds matching segments by keyword")
    func findMatchingSegments() {
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = [
            (title: "Sprint Planning", date: Date(), segments: [
                (startTime: 0, text: "We discussed the API redesign for the payments module"),
                (startTime: 30, text: "The timeline is two weeks"),
            ]),
            (title: "Design Review", date: Date(), segments: [
                (startTime: 0, text: "New dashboard mockups were presented"),
            ]),
        ]

        let results = SessionSearchLogic.findMatchingSegments(query: "API payments", sessions: sessions)
        #expect(results.count == 1)
        #expect(results[0].title == "Sprint Planning")
        #expect(results[0].relevanceScore > 0)
        #expect(!results[0].matchedExcerpts.isEmpty)
    }

    @Test("returns empty for empty query")
    func emptyQuery() {
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = [
            (title: "Meeting", date: Date(), segments: [
                (startTime: 0, text: "Some content"),
            ]),
        ]

        let results = SessionSearchLogic.findMatchingSegments(query: "", sessions: sessions)
        #expect(results.isEmpty)
    }

    @Test("returns empty when no matches")
    func noMatches() {
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = [
            (title: "Meeting", date: Date(), segments: [
                (startTime: 0, text: "Discussed lunch plans"),
            ]),
        ]

        let results = SessionSearchLogic.findMatchingSegments(query: "quantum physics", sessions: sessions)
        #expect(results.isEmpty)
    }

    @Test("search is case insensitive")
    func caseInsensitive() {
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = [
            (title: "Standup", date: Date(), segments: [
                (startTime: 0, text: "KUBERNETES deployment issue"),
            ]),
        ]

        let results = SessionSearchLogic.findMatchingSegments(query: "kubernetes", sessions: sessions)
        #expect(results.count == 1)
    }

    @Test("limits results to 5")
    func limitsToFive() {
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = (0..<10).map { i in
            (title: "Session \(i)", date: Date(), segments: [
                (startTime: 0, text: "keyword match here"),
            ])
        }

        let results = SessionSearchLogic.findMatchingSegments(query: "keyword", sessions: sessions)
        #expect(results.count == 5)
    }

    @Test("sorts by relevance score descending")
    func sortsByRelevance() {
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = [
            (title: "Low Match", date: Date(), segments: [
                (startTime: 0, text: "one mention of budget"),
            ]),
            (title: "High Match", date: Date(), segments: [
                (startTime: 0, text: "budget review and budget planning"),
                (startTime: 30, text: "budget allocation finalized"),
            ]),
        ]

        let results = SessionSearchLogic.findMatchingSegments(query: "budget", sessions: sessions)
        #expect(results.count == 2)
        #expect(results[0].title == "High Match")
        #expect(results[0].relevanceScore > results[1].relevanceScore)
    }

    @Test("limits matched excerpts to 3 per session")
    func limitsExcerpts() {
        let segments = (0..<10).map { i in
            (startTime: TimeInterval(i * 10), text: "segment \(i) with keyword")
        }
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = [
            (title: "Many Segments", date: Date(), segments: segments),
        ]

        let results = SessionSearchLogic.findMatchingSegments(query: "keyword", sessions: sessions)
        #expect(results.count == 1)
        #expect(results[0].matchedExcerpts.count == 3)
    }

    @Test("truncates long excerpt text to 100 chars")
    func truncatesExcerpts() {
        let longText = String(repeating: "keyword ", count: 50) // 400 chars
        let sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])] = [
            (title: "Long", date: Date(), segments: [
                (startTime: 0, text: longText),
            ]),
        ]

        let results = SessionSearchLogic.findMatchingSegments(query: "keyword", sessions: sessions)
        #expect(results[0].matchedExcerpts[0].count <= 100)
    }

    @Test("handles empty sessions array")
    func emptySessions() {
        let results = SessionSearchLogic.findMatchingSegments(
            query: "anything",
            sessions: []
        )
        #expect(results.isEmpty)
    }

    // MARK: - SessionSearchLogic.formatCalendarEvent

    @Test("formats all fields")
    func formatAllFields() {
        let result = SessionSearchLogic.formatCalendarEvent(
            title: "Sprint Planning",
            attendees: ["Alice", "Bob"],
            location: "Room 42",
            notes: "Discuss Q4 roadmap"
        )
        #expect(result.contains("Event: Sprint Planning"))
        #expect(result.contains("Attendees: Alice, Bob"))
        #expect(result.contains("Location: Room 42"))
        #expect(result.contains("Notes: Discuss Q4 roadmap"))
    }

    @Test("formats with missing optional fields")
    func formatMissingFields() {
        let result = SessionSearchLogic.formatCalendarEvent(
            title: "Standup",
            attendees: [],
            location: nil,
            notes: nil
        )
        #expect(result.contains("Event: Standup"))
        #expect(!result.contains("Attendees"))
        #expect(!result.contains("Location"))
        #expect(!result.contains("Notes"))
    }

    @Test("returns fallback when all fields empty")
    func formatAllEmpty() {
        let result = SessionSearchLogic.formatCalendarEvent(
            title: nil,
            attendees: [],
            location: nil,
            notes: nil
        )
        #expect(result == "No calendar event found")
    }

    @Test("truncates long notes to 200 chars")
    func formatTruncatesNotes() {
        let longNotes = String(repeating: "x", count: 500)
        let result = SessionSearchLogic.formatCalendarEvent(
            title: nil,
            attendees: [],
            location: nil,
            notes: longNotes
        )
        // "Notes: " prefix (7 chars) + 200 chars of content
        #expect(result.count <= 207)
    }

    @Test("ignores empty location string")
    func formatEmptyLocation() {
        let result = SessionSearchLogic.formatCalendarEvent(
            title: "Meeting",
            attendees: [],
            location: "",
            notes: nil
        )
        #expect(!result.contains("Location"))
    }

    @Test("ignores empty notes string")
    func formatEmptyNotes() {
        let result = SessionSearchLogic.formatCalendarEvent(
            title: "Meeting",
            attendees: [],
            location: nil,
            notes: ""
        )
        #expect(!result.contains("Notes"))
    }

    // MARK: - SessionSnippet Codable

    @Test("SessionSnippet encodes and decodes")
    func snippetCodable() throws {
        let snippet = SessionSnippet(
            title: "Test Session",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            matchedExcerpts: ["excerpt one", "excerpt two"],
            relevanceScore: 5
        )

        let data = try JSONEncoder().encode(snippet)
        let decoded = try JSONDecoder().decode(SessionSnippet.self, from: data)

        #expect(decoded.title == snippet.title)
        #expect(decoded.matchedExcerpts == snippet.matchedExcerpts)
        #expect(decoded.relevanceScore == snippet.relevanceScore)
        #expect(abs(decoded.date.timeIntervalSince(snippet.date)) < 1)
    }

    @Test("SessionSnippet equatable")
    func snippetEquatable() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SessionSnippet(title: "A", date: date, matchedExcerpts: ["x"], relevanceScore: 3)
        let b = SessionSnippet(title: "A", date: date, matchedExcerpts: ["x"], relevanceScore: 3)
        let c = SessionSnippet(title: "B", date: date, matchedExcerpts: ["x"], relevanceScore: 3)

        #expect(a == b)
        #expect(a != c)
    }
}
