import Testing
import Foundation
@testable import notetaker

struct TranscriptSegmentTests {
    @Test func initWithDefaults() {
        let segment = TranscriptSegment(startTime: 0.0, endTime: 1.5, text: "Hello")
        #expect(segment.text == "Hello")
        #expect(segment.startTime == 0.0)
        #expect(segment.endTime == 1.5)
        #expect(segment.confidence == 1.0)
        #expect(segment.language == nil)
        #expect(segment.speakerLabel == nil)
    }

    @Test func initWithAllParams() {
        let id = UUID()
        let segment = TranscriptSegment(
            id: id,
            startTime: 5.0,
            endTime: 10.0,
            text: "Test",
            confidence: 0.85,
            language: "en-US",
            speakerLabel: "Speaker 1"
        )
        #expect(segment.id == id)
        #expect(segment.confidence == 0.85)
        #expect(segment.language == "en-US")
        #expect(segment.speakerLabel == "Speaker 1")
    }
}
