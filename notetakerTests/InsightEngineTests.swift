import Testing
import Foundation
@testable import notetaker

@Suite("InsightEngine")
struct InsightEngineTests {

    @Test func emptySessionsDigest() {
        let digest = InsightEngine.generateWeeklyDigest(sessions: [])
        #expect(digest.sessionCount == 0)
        #expect(digest.totalDurationSeconds == 0)
        #expect(digest.averageDurationSeconds == 0)
        #expect(digest.busiestDay == nil)
    }

    @Test func singleSessionDigest() {
        let calendar = Calendar.current
        let now = Date()
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let lastWeekMid = calendar.date(byAdding: .day, value: -3, to: thisWeekStart)!

        let session = InsightEngine.InsightSessionData(
            id: UUID(), title: "Standup", startedAt: lastWeekMid, duration: 1800
        )
        let digest = InsightEngine.generateWeeklyDigest(sessions: [session], referenceDate: now)
        #expect(digest.sessionCount == 1)
        #expect(digest.totalDurationSeconds == 1800)
        #expect(digest.averageDurationSeconds == 1800)
    }

    @Test func weekOverWeekComparison() {
        let calendar = Calendar.current
        let now = Date()
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let lastWeekMid = calendar.date(byAdding: .day, value: -3, to: thisWeekStart)!
        let twoWeeksAgoMid = calendar.date(byAdding: .day, value: -10, to: thisWeekStart)!

        let sessions = [
            InsightEngine.InsightSessionData(id: UUID(), title: "A", startedAt: lastWeekMid, duration: 3600),
            InsightEngine.InsightSessionData(id: UUID(), title: "B", startedAt: lastWeekMid, duration: 1800),
            InsightEngine.InsightSessionData(id: UUID(), title: "C", startedAt: twoWeeksAgoMid, duration: 2700),
        ]
        let digest = InsightEngine.generateWeeklyDigest(sessions: sessions, referenceDate: now)
        #expect(digest.sessionCount == 2)
        #expect(digest.previousWeekSessionCount == 1)
        #expect(digest.sessionCountDelta == 1)
    }

    @Test func formatDurationMinutesOnly() {
        #expect(InsightEngine.formatDuration(1500) == "25m")
    }

    @Test func formatDurationHoursAndMinutes() {
        #expect(InsightEngine.formatDuration(5400) == "1h 30m")
    }

    @Test func formatDurationZero() {
        #expect(InsightEngine.formatDuration(0) == "0m")
    }

    @Test func formatDigestEmpty() {
        let digest = InsightEngine.generateWeeklyDigest(sessions: [])
        let text = InsightEngine.formatDigest(digest)
        #expect(text.contains("No meetings this week"))
    }

    @Test func formatDigestWithSessions() {
        let calendar = Calendar.current
        let now = Date()
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let lastWeekMid = calendar.date(byAdding: .day, value: -3, to: thisWeekStart)!

        let sessions = [
            InsightEngine.InsightSessionData(id: UUID(), title: "A", startedAt: lastWeekMid, duration: 3600),
            InsightEngine.InsightSessionData(id: UUID(), title: "B", startedAt: lastWeekMid, duration: 1800),
        ]
        let digest = InsightEngine.generateWeeklyDigest(sessions: sessions, referenceDate: now)
        let text = InsightEngine.formatDigest(digest)
        #expect(text.contains("2 meetings"))
        #expect(text.contains("1h 30m total"))
    }

    @Test func durationChangePercent() {
        let digest = InsightEngine.WeeklyDigest(
            weekStart: Date(), weekEnd: Date(),
            sessionCount: 5, totalDurationSeconds: 10000,
            averageDurationSeconds: 2000, busiestDay: "Monday",
            busiestDayCount: 3, previousWeekSessionCount: 4,
            previousWeekTotalDuration: 8000
        )
        #expect(digest.durationChangePercent == 25)
        #expect(digest.sessionCountDelta == 1)
    }

    @Test func durationChangePercentNoPreviousWeek() {
        let digest = InsightEngine.WeeklyDigest(
            weekStart: Date(), weekEnd: Date(),
            sessionCount: 3, totalDurationSeconds: 5000,
            averageDurationSeconds: 1666, busiestDay: nil,
            busiestDayCount: 0, previousWeekSessionCount: 0,
            previousWeekTotalDuration: 0
        )
        #expect(digest.durationChangePercent == nil)
    }

    @Test func busiestDayCalculation() {
        let calendar = Calendar.current
        let now = Date()
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let day1 = calendar.date(byAdding: .day, value: -4, to: thisWeekStart)!
        let day2 = calendar.date(byAdding: .day, value: -2, to: thisWeekStart)!

        let sessions = [
            InsightEngine.InsightSessionData(id: UUID(), title: "A", startedAt: day1, duration: 1000),
            InsightEngine.InsightSessionData(id: UUID(), title: "B", startedAt: day1, duration: 1000),
            InsightEngine.InsightSessionData(id: UUID(), title: "C", startedAt: day1, duration: 1000),
            InsightEngine.InsightSessionData(id: UUID(), title: "D", startedAt: day2, duration: 1000),
        ]
        let digest = InsightEngine.generateWeeklyDigest(sessions: sessions, referenceDate: now)
        #expect(digest.busiestDayCount == 3)
        #expect(digest.busiestDay != nil)
    }

    @Test func notificationIdentifierConstant() {
        #expect(InsightNotificationService.weeklyDigestIdentifier == "com.notetaker.weeklyDigest")
    }
}
