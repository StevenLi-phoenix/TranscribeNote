import Testing
import Foundation
@testable import notetaker

@Suite("RecordingSession Extended Tests")
struct RecordingSessionExtendedTests {

    @Test func defaultInit() {
        let session = RecordingSession()
        #expect(!session.id.uuidString.isEmpty)
        #expect(session.endedAt == nil)
        #expect(session.title == "")
        #expect(session.audioFilePath == nil)
        #expect(session.audioFilePaths.isEmpty)
        #expect(session.tags.isEmpty)
        #expect(session.segments.isEmpty)
        #expect(session.summaries.isEmpty)
        #expect(session.isPartial == false)
        #expect(session.scheduledRecordingID == nil)
    }

    @Test func customInit() {
        let id = UUID()
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let schedID = UUID()
        let session = RecordingSession(
            id: id,
            startedAt: start,
            endedAt: end,
            title: "Test Session",
            audioFilePath: "clip1.m4a",
            audioFilePaths: ["clip1.m4a", "clip2.m4a"],
            tags: ["meeting", "important"],
            segments: [],
            summaries: [],
            isPartial: true,
            scheduledRecordingID: schedID
        )
        #expect(session.id == id)
        #expect(session.startedAt == start)
        #expect(session.endedAt == end)
        #expect(session.title == "Test Session")
        #expect(session.audioFilePath == "clip1.m4a")
        #expect(session.audioFilePaths.count == 2)
        #expect(session.tags.count == 2)
        #expect(session.isPartial == true)
        #expect(session.scheduledRecordingID == schedID)
    }

    @Test func totalDurationWithEndDate() {
        let start = Date()
        let end = start.addingTimeInterval(1800)
        let session = RecordingSession(startedAt: start, endedAt: end)
        #expect(session.totalDuration == 1800)
    }

    @Test func totalDurationWithoutEndDate() {
        let session = RecordingSession(startedAt: Date(), endedAt: nil)
        #expect(session.totalDuration == 0)
    }

    @Test func audioFileURLsEmpty() {
        let session = RecordingSession()
        #expect(session.audioFileURLs.isEmpty)
        #expect(session.audioFileURL == nil)
    }
}

// MARK: - TranscriptResult Tests

@Suite("TranscriptResult Tests")
struct TranscriptResultTests {

    @Test func initWithAllFields() {
        let result = TranscriptResult(
            text: "Hello world",
            startTime: 1.0,
            endTime: 3.5,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        #expect(result.text == "Hello world")
        #expect(result.startTime == 1.0)
        #expect(result.endTime == 3.5)
        #expect(result.confidence == 0.95)
        #expect(result.language == "en-US")
        #expect(result.isFinal == true)
    }

    @Test func initWithNilLanguage() {
        let result = TranscriptResult(
            text: "Test",
            startTime: 0,
            endTime: 1,
            confidence: 0.8,
            language: nil,
            isFinal: false
        )
        #expect(result.language == nil)
        #expect(result.isFinal == false)
    }

    @Test func partialResult() {
        let result = TranscriptResult(
            text: "Partial",
            startTime: 0,
            endTime: 0.5,
            confidence: 0.5,
            language: "zh",
            isFinal: false
        )
        #expect(result.isFinal == false)
        #expect(result.text == "Partial")
    }
}

// MARK: - TranscriptSegment Extended Tests

@Suite("TranscriptSegment Extended Tests")
struct TranscriptSegmentExtendedTests {

    @Test func initDefaultValues() {
        let segment = TranscriptSegment(
            startTime: 0,
            endTime: 5.0,
            text: "Hello",
            confidence: 0.9,
            language: "en"
        )
        #expect(!segment.id.uuidString.isEmpty)
        #expect(segment.startTime == 0)
        #expect(segment.endTime == 5.0)
        #expect(segment.text == "Hello")
        #expect(segment.confidence == 0.9)
        #expect(segment.language == "en")
    }

    @Test func initWithNilLanguage() {
        let segment = TranscriptSegment(
            startTime: 10,
            endTime: 15,
            text: "Test",
            confidence: 0.7,
            language: nil
        )
        #expect(segment.language == nil)
    }
}
