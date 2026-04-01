import Testing
import Foundation
@testable import TranscribeNote

struct RecordingViewModelTests {
    @Test func initialState() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )
        #expect(vm.state == .idle)
        #expect(vm.isRecording == false)
        #expect(vm.segments.isEmpty)
        #expect(vm.partialText == "")
        #expect(vm.clock.elapsedTime == 0)
        #expect(vm.errorMessage == nil)
        #expect(vm.clock.formatted == "00:00:00")
    }

    @Test func clockFormattedDefault() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )
        #expect(vm.clock.formatted == "00:00:00")
    }

    @Test func handlePartialResult() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        let result = TranscriptResult(
            text: "Hello",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.9,
            language: "en-US",
            isFinal: false
        )
        await mock.simulateResult(result)

        try await waitForCondition { vm.partialText == "Hello" }

        #expect(vm.partialText == "Hello")
        #expect(vm.segments.isEmpty)
    }

    @Test func handleFinalResult() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        let result = TranscriptResult(
            text: "Hello world",
            startTime: 0.0,
            endTime: 2.0,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(result)

        try await waitForCondition { vm.segments.count == 1 }

        #expect(vm.segments.count == 1)
        #expect(vm.segments.first?.text == "Hello world")
        #expect(vm.partialText == "")
    }

    @Test func handleError() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        mock.simulateError(MockASREngine.MockError(message: "Test error"))

        try await waitForCondition { vm.errorMessage != nil }

        #expect(vm.errorMessage != nil)
    }

    @Test func stopRecordingWhenIdle() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        vm.stopRecording()

        #expect(vm.state == .idle)
        #expect(mock.stopCallCount == 0)
    }

    @Test func dismissCompletedRecordingClearsState() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        // Add some segments via ASR callback
        let result = TranscriptResult(
            text: "Hello world",
            startTime: 0.0,
            endTime: 2.0,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(result)
        try await waitForCondition { vm.segments.count == 1 }

        // dismissCompletedRecording should only work from .completed state
        // From .idle it should be a no-op
        vm.dismissCompletedRecording()
        #expect(vm.segments.count == 1, "Should not clear from idle state")
    }

    @Test func handleDuplicateFinalResult() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        let result = TranscriptResult(
            text: "Hello world",
            startTime: 0.0,
            endTime: 2.0,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(result)
        try await waitForCondition { vm.segments.count == 1 }

        // Send exact duplicate — should be skipped
        await mock.simulateResult(result)
        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.segments.count == 1)
        #expect(vm.partialText == "")
    }

    @Test func handleNonDuplicateSequentialFinals() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        let first = TranscriptResult(
            text: "Hello world",
            startTime: 0.0,
            endTime: 2.0,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(first)
        try await waitForCondition { vm.segments.count == 1 }

        let second = TranscriptResult(
            text: "How are you",
            startTime: 2.0,
            endTime: 4.0,
            confidence: 0.9,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(second)
        try await waitForCondition { vm.segments.count == 2 }

        #expect(vm.segments.count == 2)
        #expect(vm.segments[0].text == "Hello world")
        #expect(vm.segments[1].text == "How are you")
    }

    @Test func handlePartialAfterFinal() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        let finalResult = TranscriptResult(
            text: "Hello world",
            startTime: 0.0,
            endTime: 2.0,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(finalResult)
        try await waitForCondition { vm.segments.count == 1 }

        let partial = TranscriptResult(
            text: "Next words",
            startTime: 2.0,
            endTime: 3.0,
            confidence: 0.8,
            language: "en-US",
            isFinal: false
        )
        await mock.simulateResult(partial)
        try await waitForCondition { vm.partialText == "Next words" }

        #expect(vm.segments.count == 1)
        #expect(vm.partialText == "Next words")
    }

    @Test func multipleResults() async throws {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )

        let partial = TranscriptResult(
            text: "Working",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.8,
            language: "en-US",
            isFinal: false
        )
        await mock.simulateResult(partial)
        try await waitForCondition { vm.partialText == "Working" }
        #expect(vm.partialText == "Working")

        let final1 = TranscriptResult(
            text: "Working on it",
            startTime: 0.0,
            endTime: 2.0,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(final1)
        try await waitForCondition { vm.segments.count == 1 }

        #expect(vm.segments.count == 1)
        #expect(vm.partialText == "")

        let final2 = TranscriptResult(
            text: "Second sentence",
            startTime: 2.0,
            endTime: 4.0,
            confidence: 0.9,
            language: "en-US",
            isFinal: true
        )
        await mock.simulateResult(final2)
        try await waitForCondition { vm.segments.count == 2 }

        #expect(vm.segments.count == 2)
        #expect(vm.segments[1].text == "Second sentence")
    }
}
