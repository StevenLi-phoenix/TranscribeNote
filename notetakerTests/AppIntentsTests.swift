import Testing
import Foundation
import AppIntents
@testable import notetaker

private typealias NotetakerError = notetaker.AppIntentError

@Suite("AppIntentsTests")
struct AppIntentsTests {

    // MARK: - AppIntentError

    @Test("AppIntentError has correct localized descriptions")
    func errorDescriptions() {
        let appNotRunning = NotetakerError.appNotRunning
        let noActive = NotetakerError.noActiveRecording
        let noSession = NotetakerError.noSessionFound

        #expect(appNotRunning.localizedStringResource.key == "Notetaker is not running")
        #expect(noActive.localizedStringResource.key == "No active recording")
        #expect(noSession.localizedStringResource.key == "No session found")
    }

    @Test("AppIntentError conforms to Error")
    func errorConformance() {
        let error: any Error = NotetakerError.appNotRunning
        #expect(error is NotetakerError)
    }

    // MARK: - SessionEntity

    @Test("SessionEntity stores correct properties")
    func sessionEntityProperties() {
        let date = Date()
        let entity = SessionEntity(
            id: "550e8400-e29b-41d4-a716-446655440000",
            title: "Team Standup",
            date: date,
            segmentCount: 42
        )

        #expect(entity.id == "550e8400-e29b-41d4-a716-446655440000")
        #expect(entity.title == "Team Standup")
        #expect(entity.date == date)
        #expect(entity.segmentCount == 42)
    }

    @Test("SessionEntity display representation is not nil")
    func sessionEntityDisplayRepresentation() {
        let date = Date()
        let entity = SessionEntity(
            id: UUID().uuidString,
            title: "Sprint Review",
            date: date,
            segmentCount: 10
        )

        // DisplayRepresentation uses string interpolation so title key is "%@"
        // Just verify it can be constructed without crashing
        let display = entity.displayRepresentation
        #expect(display.subtitle != nil)
    }

    @Test("SessionEntity type display representation has correct name")
    func sessionEntityTypeRepresentation() {
        let typeRep = SessionEntity.typeDisplayRepresentation
        #expect(typeRep.name == "Recording Session")
    }

    // MARK: - Intent metadata

    @Test("StartRecordingIntent has correct metadata")
    func startRecordingMetadata() {
        #expect(StartRecordingIntent.title == "Start Recording")
        #expect(StartRecordingIntent.openAppWhenRun == true)
    }

    @Test("StopRecordingIntent has correct metadata")
    func stopRecordingMetadata() {
        #expect(StopRecordingIntent.title == "Stop Recording")
    }

    @Test("GetLastSummaryIntent has correct metadata")
    func getLastSummaryMetadata() {
        #expect(GetLastSummaryIntent.title == "Get Meeting Summary")
    }

    @Test("SearchTranscriptsIntent has correct metadata")
    func searchTranscriptsMetadata() {
        #expect(SearchTranscriptsIntent.title == "Search Transcripts")
    }

    // MARK: - AppIntentState

    @MainActor @Test("AppIntentState.ensureReady throws when not configured")
    func ensureReadyThrows() {
        let state = AppIntentState.shared
        let savedVM = state.viewModel
        let savedContainer = state.modelContainerRef
        defer {
            state.viewModel = savedVM
            state.modelContainerRef = savedContainer
        }
        state.viewModel = nil
        state.modelContainerRef = nil

        #expect(throws: NotetakerError.self) {
            try state.ensureReady()
        }
    }
}
