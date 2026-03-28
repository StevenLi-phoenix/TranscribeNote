import Foundation
import Testing
@testable import notetaker

struct AccessibilityHelpersTests {
    // MARK: - audioLevelDescription

    @Test func audioLevelSilent() {
        #expect(AccessibilityHelpers.audioLevelDescription(0.0) == "Silent")
        #expect(AccessibilityHelpers.audioLevelDescription(0.04) == "Silent")
    }

    @Test func audioLevelQuiet() {
        #expect(AccessibilityHelpers.audioLevelDescription(0.05) == "Quiet")
        #expect(AccessibilityHelpers.audioLevelDescription(0.19) == "Quiet")
    }

    @Test func audioLevelModerate() {
        #expect(AccessibilityHelpers.audioLevelDescription(0.2) == "Moderate")
        #expect(AccessibilityHelpers.audioLevelDescription(0.49) == "Moderate")
    }

    @Test func audioLevelLoud() {
        #expect(AccessibilityHelpers.audioLevelDescription(0.5) == "Loud")
        #expect(AccessibilityHelpers.audioLevelDescription(0.79) == "Loud")
    }

    @Test func audioLevelVeryLoud() {
        #expect(AccessibilityHelpers.audioLevelDescription(0.8) == "Very loud")
        #expect(AccessibilityHelpers.audioLevelDescription(1.0) == "Very loud")
    }

    // MARK: - durationDescription

    @Test func durationZeroSeconds() {
        #expect(AccessibilityHelpers.durationDescription(0) == "0 seconds")
    }

    @Test func durationSecondsOnly() {
        #expect(AccessibilityHelpers.durationDescription(45) == "45 seconds")
    }

    @Test func durationSingularSecond() {
        #expect(AccessibilityHelpers.durationDescription(1) == "1 second")
    }

    @Test func durationMinutesAndSeconds() {
        #expect(AccessibilityHelpers.durationDescription(330) == "5 minutes, 30 seconds")
    }

    @Test func durationSingularMinute() {
        #expect(AccessibilityHelpers.durationDescription(90) == "1 minute, 30 seconds")
    }

    @Test func durationHoursMinutesSeconds() {
        #expect(AccessibilityHelpers.durationDescription(3661) == "1 hour, 1 minute, 1 second")
    }

    @Test func durationMultipleHours() {
        #expect(AccessibilityHelpers.durationDescription(7384) == "2 hours, 3 minutes, 4 seconds")
    }

    @Test func durationExactMinutes() {
        #expect(AccessibilityHelpers.durationDescription(120) == "2 minutes")
    }

    // MARK: - timestampDescription

    @Test func timestampDescription() {
        #expect(AccessibilityHelpers.timestampDescription(330) == "at 5 minutes, 30 seconds")
    }

    // MARK: - recordingStateDescription

    @Test func recordingStateRecording() {
        let result = AccessibilityHelpers.recordingStateDescription(isRecording: true, isPaused: false, elapsed: 65)
        #expect(result == "Recording in progress, 1 minute, 5 seconds elapsed")
    }

    @Test func recordingStatePaused() {
        let result = AccessibilityHelpers.recordingStateDescription(isRecording: false, isPaused: true, elapsed: 30)
        #expect(result == "Recording paused at 30 seconds")
    }

    @Test func recordingStateIdle() {
        let result = AccessibilityHelpers.recordingStateDescription(isRecording: false, isPaused: false, elapsed: 0)
        #expect(result == "Not recording")
    }

    // MARK: - sessionDescription

    @Test func sessionDescriptionFull() {
        let date = Date(timeIntervalSince1970: 1700000000) // Fixed date for deterministic test
        let result = AccessibilityHelpers.sessionDescription(
            title: "Team Meeting",
            date: date,
            duration: 1830,
            segmentCount: 42
        )
        #expect(result.hasPrefix("Team Meeting, recorded "))
        #expect(result.contains("duration 30 minutes, 30 seconds"))
        #expect(result.hasSuffix("42 transcript segments"))
    }

    @Test func sessionDescriptionSingularSegment() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let result = AccessibilityHelpers.sessionDescription(
            title: "Quick Note",
            date: date,
            duration: 10,
            segmentCount: 1
        )
        #expect(result.hasSuffix("1 transcript segment"))
    }
}
