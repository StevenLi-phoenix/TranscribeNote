import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var confidence: Double
    var language: String?
    var speakerLabel: String?

    @Relationship(inverse: \RecordingSession.segments)
    var session: RecordingSession?

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        confidence: Double = 1.0,
        language: String? = nil,
        speakerLabel: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
        self.language = language
        self.speakerLabel = speakerLabel
    }
}
