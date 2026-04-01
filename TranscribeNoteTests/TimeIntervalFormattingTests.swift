import Testing
import Foundation
@testable import TranscribeNote

@Suite("TimeInterval+Formatting")
struct TimeIntervalFormattingTests {

    // MARK: - compactDuration

    /// Helper: build expected abbreviated duration using the same formatter logic,
    /// so tests pass regardless of system locale.
    private func expectedCompact(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = totalSeconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: interval) ?? "\(totalSeconds)s"
    }

    @Test
    func compactDurationZero() {
        #expect(TimeInterval(0).compactDuration == expectedCompact(0))
    }

    @Test
    func compactDurationSubMinute() {
        #expect(TimeInterval(45).compactDuration == expectedCompact(45))
    }

    @Test
    func compactDurationExactMinute() {
        #expect(TimeInterval(60).compactDuration == expectedCompact(60))
    }

    @Test
    func compactDurationMinutesAndSeconds() {
        #expect(TimeInterval(192).compactDuration == expectedCompact(192))
    }

    @Test
    func compactDurationOverAnHour() {
        #expect(TimeInterval(3661).compactDuration == expectedCompact(3661))
    }

    @Test
    func compactDurationNegativeClampsToZero() {
        #expect(TimeInterval(-5).compactDuration == expectedCompact(0))
    }

    @Test
    func compactDurationFractionalTruncates() {
        #expect(TimeInterval(45.9).compactDuration == expectedCompact(45))
    }

    // MARK: - mmss

    @Test
    func mmssZero() {
        #expect(TimeInterval(0).mmss == "00:00")
    }

    @Test
    func mmssSubMinute() {
        #expect(TimeInterval(9).mmss == "00:09")
    }

    @Test
    func mmssExactMinute() {
        #expect(TimeInterval(60).mmss == "01:00")
    }

    @Test
    func mmssMinutesAndSeconds() {
        #expect(TimeInterval(155).mmss == "02:35")
    }

    @Test
    func mmssNegativeClampsToZero() {
        #expect(TimeInterval(-10).mmss == "00:00")
    }

    // MARK: - hhmmss

    @Test
    func hhmmssZero() {
        #expect(TimeInterval(0).hhmmss == "00:00:00")
    }

    @Test
    func hhmmssSubMinute() {
        #expect(TimeInterval(5).hhmmss == "00:00:05")
    }

    @Test
    func hhmmssMinutesOnly() {
        #expect(TimeInterval(120).hhmmss == "00:02:00")
    }

    @Test
    func hhmmssHoursMinutesSeconds() {
        #expect(TimeInterval(3723).hhmmss == "01:02:03")
    }

    @Test
    func hhmmssNegativeClampsToZero() {
        #expect(TimeInterval(-100).hhmmss == "00:00:00")
    }
}
