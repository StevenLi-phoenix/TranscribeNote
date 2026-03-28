import Testing
import Foundation
@testable import notetaker

@Suite("AnalyticsService")
struct AnalyticsServiceTests {

    // MARK: - Date Helpers

    @Test("dateKey formats date as yyyy-MM-dd")
    func dateKeyFormat() {
        let date = makeDate(year: 2026, month: 3, day: 15)
        let key = AnalyticsService.dateKey(date)
        #expect(key == "2026-03-15")
    }

    @Test("dayOfWeek returns day name")
    func dayOfWeekName() {
        // 2026-03-28 is a Saturday
        let date = makeDate(year: 2026, month: 3, day: 28)
        let day = AnalyticsService.dayOfWeek(date)
        #expect(day == "Saturday")
    }

    // MARK: - formatHoursMinutes

    @Test("formatHoursMinutes with hours and minutes")
    func formatHoursAndMinutes() {
        let result = AnalyticsService.formatHoursMinutes(8100) // 2h 15m
        #expect(result == "2h 15m")
    }

    @Test("formatHoursMinutes with minutes only")
    func formatMinutesOnly() {
        let result = AnalyticsService.formatHoursMinutes(900) // 15m
        #expect(result == "15m")
    }

    @Test("formatHoursMinutes with zero duration")
    func formatZeroDuration() {
        let result = AnalyticsService.formatHoursMinutes(0)
        #expect(result == "0m")
    }

    @Test("formatHoursMinutes with exact hours")
    func formatExactHours() {
        let result = AnalyticsService.formatHoursMinutes(7200) // 2h 0m
        #expect(result == "2h 0m")
    }

    // MARK: - dailyBuckets

    @Test("dailyBuckets fills empty days with zero")
    func dailyBucketsEmptyDays() {
        let now = makeDate(year: 2026, month: 3, day: 28)
        let buckets = AnalyticsService.dailyBuckets(sessions: [], days: 7, now: now)

        #expect(buckets.count == 7)
        for bucket in buckets {
            #expect(bucket.sessionCount == 0)
            #expect(bucket.totalDuration == 0)
        }
    }

    @Test("dailyBuckets counts sessions per day correctly")
    func dailyBucketsSessionCounts() {
        let now = makeDate(year: 2026, month: 3, day: 28)
        let sessions = [
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 28), duration: 600),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 28), duration: 300),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 27), duration: 450),
        ]

        let buckets = AnalyticsService.dailyBuckets(sessions: sessions, days: 7, now: now)
        let march28 = buckets.first { $0.id == "2026-03-28" }
        let march27 = buckets.first { $0.id == "2026-03-27" }

        #expect(march28?.sessionCount == 2)
        #expect(march27?.sessionCount == 1)
    }

    @Test("dailyBuckets accumulates duration")
    func dailyBucketsDurationAccumulation() {
        let now = makeDate(year: 2026, month: 3, day: 28)
        let sessions = [
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 28), duration: 600),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 28), duration: 300),
        ]

        let buckets = AnalyticsService.dailyBuckets(sessions: sessions, days: 7, now: now)
        let march28 = buckets.first { $0.id == "2026-03-28" }

        #expect(march28?.totalDuration == 900)
        #expect(march28?.averageDuration == 450)
    }

    @Test("dailyBuckets ignores sessions outside range")
    func dailyBucketsOutOfRange() {
        let now = makeDate(year: 2026, month: 3, day: 28)
        let sessions = [
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 20), duration: 600),
        ]

        let buckets = AnalyticsService.dailyBuckets(sessions: sessions, days: 7, now: now)
        let totalSessions = buckets.reduce(0) { $0 + $1.sessionCount }
        #expect(totalSessions == 0)
    }

    @Test("dailyBuckets returns sorted by date")
    func dailyBucketsSorted() {
        let now = makeDate(year: 2026, month: 3, day: 28)
        let buckets = AnalyticsService.dailyBuckets(sessions: [], days: 7, now: now)

        for i in 1..<buckets.count {
            #expect(buckets[i].date > buckets[i - 1].date)
        }
    }

    // MARK: - summary

    @Test("summary with empty sessions returns zeros")
    func summaryEmpty() {
        let stats = AnalyticsService.summary(sessions: [])
        #expect(stats.totalSessions == 0)
        #expect(stats.totalDuration == 0)
        #expect(stats.averageDuration == 0)
        #expect(stats.longestSession == 0)
        #expect(stats.mostActiveDay == nil)
    }

    @Test("summary calculates correct totals")
    func summaryTotals() {
        let sessions = [
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 28), duration: 600),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 27), duration: 300),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 26), duration: 900),
        ]

        let stats = AnalyticsService.summary(sessions: sessions)
        #expect(stats.totalSessions == 3)
        #expect(stats.totalDuration == 1800)
        #expect(stats.averageDuration == 600)
    }

    @Test("summary finds longest session")
    func summaryLongestSession() {
        let sessions = [
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 28), duration: 600),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 27), duration: 1200),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 26), duration: 300),
        ]

        let stats = AnalyticsService.summary(sessions: sessions)
        #expect(stats.longestSession == 1200)
    }

    @Test("summary finds most active day of week")
    func summaryMostActiveDay() {
        // 2026-03-23 = Monday, 2026-03-24 = Tuesday, 2026-03-30 = Monday
        let sessions = [
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 23), duration: 100),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 24), duration: 100),
            SessionDataPoint(date: makeDate(year: 2026, month: 3, day: 30), duration: 100),
        ]

        let stats = AnalyticsService.summary(sessions: sessions)
        #expect(stats.mostActiveDay == "Monday")
    }

    // MARK: - DailyBucket.averageDuration

    @Test("DailyBucket averageDuration with zero sessions returns 0")
    func dailyBucketAverageZero() {
        let bucket = DailyBucket(id: "test", date: Date(), sessionCount: 0, totalDuration: 0)
        #expect(bucket.averageDuration == 0)
    }

    @Test("DailyBucket averageDuration calculation")
    func dailyBucketAverageCalculation() {
        let bucket = DailyBucket(id: "test", date: Date(), sessionCount: 3, totalDuration: 900)
        #expect(bucket.averageDuration == 300)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12  // Noon to avoid timezone edge cases
        return Calendar.current.date(from: components)!
    }
}
