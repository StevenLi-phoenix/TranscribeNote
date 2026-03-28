import Foundation
import Testing
@testable import notetaker

@Suite("DateFilterCounter")
struct DateFilterBadgeTests {

    private func makeSession(daysAgo: Int) -> DateFilterCounter.SessionDate {
        DateFilterCounter.SessionDate(
            startedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        )
    }

    @Test func allFilter_returnsTotal() {
        let sessions = [makeSession(daysAgo: 0), makeSession(daysAgo: 5), makeSession(daysAgo: 40)]
        #expect(DateFilterCounter.count(for: .all, in: sessions) == 3)
    }

    @Test func todayFilter_onlyToday() {
        let sessions = [makeSession(daysAgo: 0), makeSession(daysAgo: 0), makeSession(daysAgo: 1)]
        #expect(DateFilterCounter.count(for: .today, in: sessions) == 2)
    }

    @Test func thisWeekFilter() {
        let sessions = [makeSession(daysAgo: 0), makeSession(daysAgo: 2), makeSession(daysAgo: 30)]
        let count = DateFilterCounter.count(for: .thisWeek, in: sessions)
        #expect(count >= 1) // At least today's session
    }

    @Test func thisMonthFilter() {
        let sessions = [makeSession(daysAgo: 0), makeSession(daysAgo: 10), makeSession(daysAgo: 60)]
        let count = DateFilterCounter.count(for: .thisMonth, in: sessions)
        #expect(count >= 1)
    }

    @Test func emptySessionsReturnsZero() {
        #expect(DateFilterCounter.count(for: .today, in: []) == 0)
    }

    @Test func todayFilter_excludesYesterday() {
        let sessions = [makeSession(daysAgo: 1)]
        #expect(DateFilterCounter.count(for: .today, in: sessions) == 0)
    }

    @Test func countWithFixedDate() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let sameDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 8))!
        let lastWeek = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let sameMonth = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let lastMonth = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!

        let sessions = [
            DateFilterCounter.SessionDate(startedAt: sameDay),
            DateFilterCounter.SessionDate(startedAt: lastWeek),
            DateFilterCounter.SessionDate(startedAt: sameMonth),
            DateFilterCounter.SessionDate(startedAt: lastMonth),
        ]

        #expect(DateFilterCounter.count(for: .all, in: sessions, now: now) == 4)
        #expect(DateFilterCounter.count(for: .today, in: sessions, now: now) == 1)
        #expect(DateFilterCounter.count(for: .thisMonth, in: sessions, now: now) == 3)
    }
}
