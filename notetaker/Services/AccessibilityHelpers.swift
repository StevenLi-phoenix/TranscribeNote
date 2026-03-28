import Foundation

/// Pure functions for generating accessibility descriptions.
nonisolated enum AccessibilityHelpers {
    /// Describe audio level for VoiceOver.
    static func audioLevelDescription(_ level: Float) -> String {
        switch level {
        case ..<0.05: return "Silent"
        case 0.05..<0.2: return "Quiet"
        case 0.2..<0.5: return "Moderate"
        case 0.5..<0.8: return "Loud"
        default: return "Very loud"
        }
    }

    /// Format duration for VoiceOver reading: "5 minutes, 30 seconds"
    static func durationDescription(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs) second\(secs == 1 ? "" : "s")") }

        return parts.joined(separator: ", ")
    }

    /// Format timestamp for VoiceOver: "at 5 minutes 30 seconds"
    static func timestampDescription(_ seconds: TimeInterval) -> String {
        "at \(durationDescription(seconds))"
    }

    /// Describe recording state.
    static func recordingStateDescription(isRecording: Bool, isPaused: Bool, elapsed: TimeInterval) -> String {
        if isPaused {
            return "Recording paused at \(durationDescription(elapsed))"
        } else if isRecording {
            return "Recording in progress, \(durationDescription(elapsed)) elapsed"
        } else {
            return "Not recording"
        }
    }

    /// Describe session for VoiceOver.
    static func sessionDescription(title: String, date: Date, duration: TimeInterval, segmentCount: Int) -> String {
        let dateStr = date.formatted(date: .abbreviated, time: .shortened)
        let durStr = durationDescription(duration)
        return "\(title), recorded \(dateStr), duration \(durStr), \(segmentCount) transcript segment\(segmentCount == 1 ? "" : "s")"
    }
}
