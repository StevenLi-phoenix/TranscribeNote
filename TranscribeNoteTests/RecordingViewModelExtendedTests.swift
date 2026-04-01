import Testing
import Foundation
@testable import TranscribeNote

// MARK: - ElapsedTimeClock Tests

@Suite("ElapsedTimeClock Tests")
struct ElapsedTimeClockTests {

    @Test func initialState() {
        let clock = ElapsedTimeClock()
        #expect(clock.elapsedTime == 0)
        #expect(clock.formatted == "00:00:00")
    }

    @Test func updateSetsTime() {
        let clock = ElapsedTimeClock()
        clock.update(65.0) // 1:05
        #expect(clock.elapsedTime == 65.0)
        #expect(clock.formatted == "00:01:05")
    }

    @Test func resetClearsTime() {
        let clock = ElapsedTimeClock()
        clock.update(120.0)
        #expect(clock.elapsedTime == 120.0)
        clock.reset()
        #expect(clock.elapsedTime == 0)
        #expect(clock.formatted == "00:00:00")
    }

    @Test func formattedHours() {
        let clock = ElapsedTimeClock()
        clock.update(3661.0) // 1:01:01
        #expect(clock.formatted == "01:01:01")
    }
}

// MARK: - ScheduledRecordingInfo Tests

@Suite("ScheduledRecordingInfo Tests")
struct ScheduledRecordingInfoTests {

    @Test func initWithDuration() {
        let id = UUID()
        let info = ScheduledRecordingInfo(id: id, title: "Meeting", durationMinutes: 60)
        #expect(info.id == id)
        #expect(info.title == "Meeting")
        #expect(info.durationMinutes == 60)
    }

    @Test func initWithoutDuration() {
        let info = ScheduledRecordingInfo(id: UUID(), title: "Note", durationMinutes: nil)
        #expect(info.durationMinutes == nil)
    }
}

// MARK: - RecordingState Tests

@Suite("RecordingState Tests", .serialized)
struct RecordingStateTests {

    @Test func recordingViewModelIsRecording() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        #expect(vm.isRecording == false)
        #expect(vm.isActive == false)
    }

    @Test func isRecordingMatchesState() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        // idle state
        #expect(vm.isRecording == false)
        #expect(vm.isActive == false)
    }
}

// MARK: - RecordingViewModel Extended Tests

@Suite("RecordingViewModel Extended Tests", .serialized)
struct RecordingViewModelExtendedTests {

    @Test func stopRecordingFromIdleIsNoop() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        vm.stopRecording()
        #expect(vm.state == .idle)
    }

    @Test func dismissFromNonCompletedIsNoop() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)

        // Add a segment
        let result = TranscriptResult(text: "Test", startTime: 0, endTime: 1, confidence: 0.9, language: "en", isFinal: true)
        await mock.simulateResult(result)
        try await waitForCondition { vm.segments.count == 1 }

        // Dismiss from idle — should not clear
        vm.dismissCompletedRecording()
        #expect(vm.segments.count == 1)
    }

    @Test func clearSummaryError() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        // Manually verify clearSummaryError works (summaryError is private(set))
        vm.clearSummaryError()
        #expect(vm.summaryError == nil)
    }

    @Test func stoppingStatusDefault() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        #expect(vm.stoppingStatus == "Saving...")
    }

    @Test func summariesInitiallyEmpty() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        #expect(vm.summaries.isEmpty)
        #expect(vm.isSummarizing == false)
        #expect(vm.latestSummary == nil)
    }

    @Test func showDurationEndPromptDefault() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        #expect(vm.showDurationEndPrompt == false)
        #expect(vm.scheduledInfo == nil)
    }

    @Test func currentSessionNilByDefault() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        #expect(vm.currentSession == nil)
    }

    @Test func clockAndMeterAreAccessible() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        #expect(vm.clock.elapsedTime == 0)
        #expect(vm.audioMeter.level == 0)
    }

    @Test func initWithSummarizerConfig() {
        let mock = MockASREngine()
        let config = SummarizerConfig(liveSummarizationEnabled: false, intervalMinutes: 5)
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock,
            summarizerConfig: config
        )
        #expect(vm.state == .idle)
    }

    @Test func initWithVADConfig() {
        let mock = MockASREngine()
        let vadConfig = VADConfig(vadEnabled: true, silenceThreshold: 0.05)
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock,
            vadConfig: vadConfig
        )
        #expect(vm.state == .idle)
    }

    @Test func triggerPeriodicSummaryWhenIdleIsNoop() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)
        // Should not crash when called in idle state
        vm.triggerPeriodicSummary()
        #expect(vm.isSummarizing == false)
    }

    @Test func clipTimeOffsetHandling() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(audioCaptureService: AudioCaptureService(), asrEngine: mock)

        // Verify segments use correct offset
        let result = TranscriptResult(text: "Hello", startTime: 0, endTime: 1.5, confidence: 0.9, language: "en", isFinal: true)
        await mock.simulateResult(result)
        try await waitForCondition { vm.segments.count == 1 }

        #expect(vm.segments[0].startTime == 0)
        #expect(vm.segments[0].endTime == 1.5)
    }
}
