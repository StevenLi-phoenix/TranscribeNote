import Foundation

extension TimeInterval {
    /// Compact human-readable duration, e.g. "3m 12s", "1h 30m", or "45s".
    /// Handles hours and drops trailing zero components.
    var compactDuration: String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
        if minutes > 0 {
            if seconds > 0 {
                return "\(minutes)m \(seconds)s"
            }
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }

    /// Zero-padded mm:ss timestamp, e.g. "02:35".
    var mmss: String {
        let totalSeconds = max(0, Int(self))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Zero-padded hh:mm:ss timestamp, e.g. "01:02:35".
    var hhmmss: String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
