import Foundation
import os

/// Tracks cumulative token usage across sessions, stored daily in UserDefaults.
nonisolated enum TokenUsageTracker {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "TokenUsageTracker")
    static let storageKey = "tokenUsageDaily"

    struct DailyUsage: Codable, Sendable, Equatable {
        var promptTokens: Int = 0
        var completionTokens: Int = 0
        var requestCount: Int = 0
        var estimatedCost: Double = 0

        var totalTokens: Int { promptTokens + completionTokens }
    }

    /// Record a token usage event.
    static func record(usage: TokenUsage, estimatedCost: Double?, date: Date = Date(), defaults: UserDefaults = .standard) {
        var daily = loadDaily(defaults: defaults)
        let key = dateKey(date)
        var entry = daily[key] ?? DailyUsage()
        entry.promptTokens += usage.inputTokens
        entry.completionTokens += usage.outputTokens
        entry.requestCount += 1
        entry.estimatedCost += estimatedCost ?? 0
        daily[key] = entry
        saveDaily(daily, defaults: defaults)
        logger.debug("Recorded \(usage.inputTokens + usage.outputTokens) tokens for \(key)")
    }

    /// Get usage for a date range.
    static func usage(from startDate: Date, to endDate: Date, defaults: UserDefaults = .standard) -> DailyUsage {
        let daily = loadDaily(defaults: defaults)
        var total = DailyUsage()
        var current = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)

        while current <= end {
            if let entry = daily[dateKey(current)] {
                total.promptTokens += entry.promptTokens
                total.completionTokens += entry.completionTokens
                total.requestCount += entry.requestCount
                total.estimatedCost += entry.estimatedCost
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return total
    }

    /// Get total tokens for today.
    static func todayUsage(defaults: UserDefaults = .standard) -> DailyUsage {
        let today = Date()
        return usage(from: today, to: today, defaults: defaults)
    }

    /// Get total tokens for last 7 days.
    static func weekUsage(defaults: UserDefaults = .standard) -> DailyUsage {
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: now)!
        return usage(from: weekAgo, to: now, defaults: defaults)
    }

    /// Get total tokens for last 30 days.
    static func monthUsage(defaults: UserDefaults = .standard) -> DailyUsage {
        let now = Date()
        let monthAgo = Calendar.current.date(byAdding: .day, value: -29, to: now)!
        return usage(from: monthAgo, to: now, defaults: defaults)
    }

    /// Reset all usage data.
    static func resetAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
        logger.info("Token usage data reset")
    }

    // MARK: - Internal (visible for testing)

    static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func loadDaily(defaults: UserDefaults = .standard) -> [String: DailyUsage] {
        guard let data = defaults.data(forKey: storageKey),
              let daily = try? JSONDecoder().decode([String: DailyUsage].self, from: data) else {
            return [:]
        }
        return daily
    }

    private static func saveDaily(_ daily: [String: DailyUsage], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(daily) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
