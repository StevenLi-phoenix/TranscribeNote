import Testing
import Foundation
@testable import TranscribeNote

struct RecordingSessionTests {
    @Test func initWithDefaults() {
        let session = RecordingSession()
        #expect(session.title == "")
        #expect(session.endedAt == nil)
        #expect(session.audioFilePath == nil)
        #expect(session.tags.isEmpty)
        #expect(session.segments.isEmpty)
        #expect(session.totalDuration == 0)
    }

    @Test func totalDurationCalculation() {
        let start = Date()
        let end = start.addingTimeInterval(120)
        let session = RecordingSession(startedAt: start, endedAt: end, title: "Test Session")
        #expect(session.totalDuration == 120)
    }

    @Test func totalDurationWhenNotEnded() {
        let session = RecordingSession(title: "In Progress")
        #expect(session.totalDuration == 0)
    }
}
