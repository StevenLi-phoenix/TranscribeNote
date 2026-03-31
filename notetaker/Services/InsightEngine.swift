import Foundation
import os

/// Computes meeting insights and weekly digest statistics.
nonisolated enum InsightEngine {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "InsightEngine")

    /// Lightweight session data for cross-isolation use.
    struct InsightSessionData: Sendable {
        let id: UUID
        let title: String
        let startedAt: Date
        let duration: TimeInterval
    }

    /// Weekly meeting digest statistics.
    struct WeeklyDigest: Sendable {
        let weekStart: Date
        let weekEnd: Date
        let sessionCount: Int
        let totalDurationSeconds: TimeInterval
        let averageDurationSeconds: TimeInterval
        let busiestDay: String?
        let busiestDayCount: Int
        let previousWeekSessionCount: Int
        let previousWeekTotalDuration: TimeInterval

        /// Week-over-week change in session count (e.g. +2 or -1).
        var sessionCountDelta: Int { sessionCount - previousWeekSessionCount }

        /// Week-over-week change in total duration.
        var durationDelta: TimeInterval { totalDurationSeconds - previousWeekTotalDuration }

        /// Percentage change in meeting time vs last week.
        var durationChangePercent: Int? {
            guard previousWeekTotalDuration > 0 else { return nil }
            return Int((durationDelta / previousWeekTotalDuration) * 100)
        }
    }

    // MARK: - Digest Generation

    /// Generate a weekly digest from session data.
    /// - Parameters:
    ///   - sessions: All sessions to consider.
    ///   - referenceDate: The date to compute "this week" from (defaults to now).
    ///   - calendar: Calendar for week computation.
    /// - Returns: WeeklyDigest with stats for the most recent complete week.
    static func generateWeeklyDigest(
        sessions: [InsightSessionData],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyDigest {
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? referenceDate
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart

        // "This week" digest covers the most recent *complete* week (lastWeekStart ..< thisWeekStart)
        let thisWeekSessions = sessions.filter { $0.startedAt >= lastWeekStart && $0.startedAt < thisWeekStart }

        // Previous week for comparison
        let prevWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: lastWeekStart) ?? lastWeekStart
        let prevWeekSessions = sessions.filter { $0.startedAt >= prevWeekStart && $0.startedAt < lastWeekStart }

        let totalDuration = thisWeekSessions.reduce(0) { $0 + $1.duration }
        let avgDuration = thisWeekSessions.isEmpty ? 0 : totalDuration / Double(thisWeekSessions.count)

        // Find busiest day of the week
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        var dayCounts: [String: Int] = [:]
        for session in thisWeekSessions {
            let day = dayFormatter.string(from: session.startedAt)
            dayCounts[day, default: 0] += 1
        }
        let busiest = dayCounts.max(by: { $0.value < $1.value })

        let prevTotalDuration = prevWeekSessions.reduce(0) { $0 + $1.duration }
        let weekEnd = calendar.date(byAdding: .day, value: -1, to: thisWeekStart) ?? thisWeekStart

        logger.debug("Weekly digest: \(thisWeekSessions.count) sessions, \(Int(totalDuration))s total")

        return WeeklyDigest(
            weekStart: lastWeekStart,
            weekEnd: weekEnd,
            sessionCount: thisWeekSessions.count,
            totalDurationSeconds: totalDuration,
            averageDurationSeconds: avgDuration,
            busiestDay: busiest?.key,
            busiestDayCount: busiest?.value ?? 0,
            previousWeekSessionCount: prevWeekSessions.count,
            previousWeekTotalDuration: prevTotalDuration
        )
    }

    // MARK: - Formatting

    /// Format a WeeklyDigest into a human-readable summary string.
    static func formatDigest(_ digest: WeeklyDigest) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        var lines = [String]()
        lines.append("Weekly Meeting Recap (\(dateFormatter.string(from: digest.weekStart)) – \(dateFormatter.string(from: digest.weekEnd)))")
        lines.append("")

        if digest.sessionCount == 0 {
            lines.append("No meetings this week.")
            return lines.joined(separator: "\n")
        }

        lines.append("• \(digest.sessionCount) meeting\(digest.sessionCount == 1 ? "" : "s"), \(formatDuration(digest.totalDurationSeconds)) total")
        lines.append("• Average duration: \(formatDuration(digest.averageDurationSeconds))")

        if let busiest = digest.busiestDay {
            lines.append("• Busiest day: \(busiest) (\(digest.busiestDayCount) meeting\(digest.busiestDayCount == 1 ? "" : "s"))")
        }

        if digest.previousWeekSessionCount > 0 {
            let delta = digest.sessionCountDelta
            let sign = delta >= 0 ? "+" : ""
            lines.append("")
            lines.append("vs. last week: \(sign)\(delta) meeting\(abs(delta) == 1 ? "" : "s")")
            if let pct = digest.durationChangePercent {
                let pctSign = pct >= 0 ? "+" : ""
                lines.append("Meeting time: \(pctSign)\(pct)%")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Format duration as "Xh Ym" or "Ym" for shorter durations.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Build InsightSessionData from a RecordingSession (call on MainActor).
    static func sessionData(from session: RecordingSession) -> InsightSessionData {
        InsightSessionData(
            id: session.id,
            title: session.title,
            startedAt: session.startedAt,
            duration: session.totalDuration
        )
    }
}
