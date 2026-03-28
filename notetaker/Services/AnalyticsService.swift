import Foundation
import os

/// A single session's data point for analytics.
nonisolated struct SessionDataPoint: Sendable {
    let date: Date
    let duration: TimeInterval
}

/// Aggregated daily bucket.
nonisolated struct DailyBucket: Identifiable, Sendable {
    let id: String  // "yyyy-MM-dd"
    let date: Date
    var sessionCount: Int
    var totalDuration: TimeInterval
    var averageDuration: TimeInterval { sessionCount > 0 ? totalDuration / Double(sessionCount) : 0 }
}

/// Overall stats summary.
nonisolated struct AnalyticsSummary: Sendable {
    let totalSessions: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let longestSession: TimeInterval
    let mostActiveDay: String?  // "Monday" etc.
}

/// Pure analytics aggregation functions — no SwiftData dependency.
nonisolated enum AnalyticsService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "AnalyticsService"
    )

    // MARK: - Date Helpers

    static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    // MARK: - Aggregation

    /// Group sessions into daily buckets, filling empty days with 0.
    static func dailyBuckets(sessions: [SessionDataPoint], days: Int, now: Date = Date()) -> [DailyBucket] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!

        // Create empty buckets for every day in range
        var buckets: [String: DailyBucket] = [:]
        for i in 0..<days {
            let date = calendar.date(byAdding: .day, value: i, to: startDate)!
            let key = dateKey(date)
            buckets[key] = DailyBucket(id: key, date: date, sessionCount: 0, totalDuration: 0)
        }

        // Fill with session data
        for session in sessions {
            let key = dateKey(session.date)
            if var bucket = buckets[key] {
                bucket.sessionCount += 1
                bucket.totalDuration += session.duration
                buckets[key] = bucket
            }
        }

        logger.debug("Aggregated \(sessions.count) sessions into \(buckets.count) daily buckets")
        return buckets.values.sorted { $0.date < $1.date }
    }

    /// Calculate overall summary stats.
    static func summary(sessions: [SessionDataPoint]) -> AnalyticsSummary {
        guard !sessions.isEmpty else {
            return AnalyticsSummary(
                totalSessions: 0,
                totalDuration: 0,
                averageDuration: 0,
                longestSession: 0,
                mostActiveDay: nil
            )
        }

        let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
        let avgDuration = totalDuration / Double(sessions.count)
        let longest = sessions.max(by: { $0.duration < $1.duration })?.duration ?? 0

        // Most active day of week
        var dayCounts: [String: Int] = [:]
        for session in sessions {
            let day = dayOfWeek(session.date)
            dayCounts[day, default: 0] += 1
        }
        let mostActive = dayCounts.max(by: { $0.value < $1.value })?.key

        logger.debug("Summary: \(sessions.count) sessions, total \(Int(totalDuration))s, avg \(Int(avgDuration))s")
        return AnalyticsSummary(
            totalSessions: sessions.count,
            totalDuration: totalDuration,
            averageDuration: avgDuration,
            longestSession: longest,
            mostActiveDay: mostActive
        )
    }

    /// Format duration as hours and minutes: "2h 15m".
    static func formatHoursMinutes(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let mins = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}
