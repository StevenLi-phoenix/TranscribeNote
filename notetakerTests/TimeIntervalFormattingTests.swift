import Testing
import Foundation
@testable import notetaker

@Suite("TimeInterval+Formatting")
struct TimeIntervalFormattingTests {

    // MARK: - compactDuration

    @Test
    func compactDurationZero() {
        #expect(TimeInterval(0).compactDuration == "0s")
    }

    @Test
    func compactDurationSubMinute() {
        #expect(TimeInterval(45).compactDuration == "45s")
    }

    @Test
    func compactDurationExactMinute() {
        #expect(TimeInterval(60).compactDuration == "1m 0s")
    }

    @Test
    func compactDurationMinutesAndSeconds() {
        #expect(TimeInterval(192).compactDuration == "3m 12s")
    }

    @Test
    func compactDurationOverAnHour() {
        #expect(TimeInterval(3661).compactDuration == "61m 1s")
    }

    @Test
    func compactDurationNegativeClampsToZero() {
        #expect(TimeInterval(-5).compactDuration == "0s")
    }

    @Test
    func compactDurationFractionalTruncates() {
        #expect(TimeInterval(45.9).compactDuration == "45s")
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
