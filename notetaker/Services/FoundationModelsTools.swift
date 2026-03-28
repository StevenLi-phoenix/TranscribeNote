import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Pure Logic (testable without FoundationModels)

/// Pure search logic for finding matching session segments — `nonisolated` for testability.
nonisolated enum SessionSearchLogic {
    private static let logger = Logger(subsystem: "com.notetaker", category: "SessionSearchLogic")

    /// Search session segments for keyword matches and return ranked snippets.
    static func findMatchingSegments(
        query: String,
        sessions: [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])]
    ) -> [SessionSnippet] {
        let keywords = query.lowercased().split(separator: " ").map(String.init)
        guard !keywords.isEmpty else {
            logger.debug("Empty query keywords — returning no results")
            return []
        }

        var results: [SessionSnippet] = []

        for session in sessions {
            var matchCount = 0
            var matchedTexts: [String] = []

            for seg in session.segments {
                let lower = seg.text.lowercased()
                let matches = keywords.filter { lower.contains($0) }.count
                if matches > 0 {
                    matchCount += matches
                    if matchedTexts.count < 3 {
                        matchedTexts.append(String(seg.text.prefix(100)))
                    }
                }
            }

            if matchCount > 0 {
                results.append(SessionSnippet(
                    title: session.title,
                    date: session.date,
                    matchedExcerpts: matchedTexts,
                    relevanceScore: matchCount
                ))
            }
        }

        let sorted = Array(results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(5))
        logger.info("Session search for '\(query)': \(sorted.count) result(s) from \(sessions.count) session(s)")
        return sorted
    }

    /// Format calendar event info into a readable string for LLM context.
    static func formatCalendarEvent(
        title: String?,
        attendees: [String],
        location: String?,
        notes: String?
    ) -> String {
        var parts: [String] = []
        if let title { parts.append("Event: \(title)") }
        if !attendees.isEmpty { parts.append("Attendees: \(attendees.joined(separator: ", "))") }
        if let location, !location.isEmpty { parts.append("Location: \(location)") }
        if let notes, !notes.isEmpty { parts.append("Notes: \(String(notes.prefix(200)))") }
        return parts.isEmpty ? "No calendar event found" : parts.joined(separator: "\n")
    }
}

/// Lightweight snippet for search results.
nonisolated struct SessionSnippet: Codable, Sendable, Equatable {
    let title: String
    let date: Date
    let matchedExcerpts: [String]
    let relevanceScore: Int
}

// MARK: - Foundation Models Native Tools

#if canImport(FoundationModels)

/// Foundation Models Tool for searching historical session transcripts.
@available(macOS 26, *)
nonisolated struct RelatedSessionSearchTool: Tool {
    private static let logger = Logger(subsystem: "com.notetaker", category: "RelatedSessionSearchTool")

    let name = "searchRelatedSessions"
    let description = "Search historical meeting transcripts for content related to a query topic"

    @Generable
    struct Arguments {
        @Guide(description: "The topic or keywords to search for in previous session transcripts")
        var query: String
    }

    /// Closure providing session data for search (injected, avoids SwiftData dependency).
    var sessionProvider: @Sendable () async -> [(title: String, date: Date, segments: [(startTime: TimeInterval, text: String)])]

    nonisolated func call(arguments: Arguments) async throws -> String {
        Self.logger.info("Searching related sessions for: '\(arguments.query)'")
        let sessions = await sessionProvider()
        let snippets = SessionSearchLogic.findMatchingSegments(query: arguments.query, sessions: sessions)

        if snippets.isEmpty {
            Self.logger.info("No related sessions found for: '\(arguments.query)'")
            return "No related sessions found for: \(arguments.query)"
        }

        let text = snippets.map { snippet in
            var entry = "[\(snippet.title) - \(snippet.date.formatted(date: .abbreviated, time: .omitted))]"
            for excerpt in snippet.matchedExcerpts {
                entry += "\n  \(excerpt)"
            }
            return entry
        }.joined(separator: "\n\n")

        Self.logger.info("Found \(snippets.count) related session(s)")
        return text
    }
}

/// Foundation Models Tool for looking up the current calendar event.
@available(macOS 26, *)
nonisolated struct CalendarEventLookupTool: Tool {
    private static let logger = Logger(subsystem: "com.notetaker", category: "CalendarEventLookupTool")

    let name = "lookupCalendarEvent"
    let description = "Look up calendar event details for the current recording session, including title, attendees, and location"

    @Generable
    struct Arguments {
        @Guide(description: "Time description such as 'current' or 'now' for the current event")
        var timeDescription: String
    }

    /// Closure providing calendar event data (injected, avoids EventKit dependency in tests).
    var calendarProvider: @Sendable () async -> (title: String?, attendees: [String], location: String?, notes: String?)

    nonisolated func call(arguments: Arguments) async throws -> String {
        Self.logger.info("Looking up calendar event (time: '\(arguments.timeDescription)')")
        let event = await calendarProvider()
        let formatted = SessionSearchLogic.formatCalendarEvent(
            title: event.title,
            attendees: event.attendees,
            location: event.location,
            notes: event.notes
        )
        Self.logger.info("Calendar lookup result: \(formatted.prefix(80))...")
        return formatted
    }
}

#endif
