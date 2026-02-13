import Testing
import Foundation
@testable import notetaker

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
        #expect(vm.elapsedTime == 0)
        #expect(vm.errorMessage == nil)
        #expect(vm.formattedElapsedTime == "00:00:00")
    }

    @Test func formattedElapsedTime() {
        let mock = MockASREngine()
        let vm = RecordingViewModel(
            audioCaptureService: AudioCaptureService(),
            asrEngine: mock
        )
        #expect(vm.formattedElapsedTime == "00:00:00")
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
        mock.simulateResult(result)

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
        mock.simulateResult(result)

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
        mock.simulateResult(result)
        try await waitForCondition { vm.segments.count == 1 }

        // Send exact duplicate — should be skipped
        mock.simulateResult(result)
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
        mock.simulateResult(first)
        try await waitForCondition { vm.segments.count == 1 }

        let second = TranscriptResult(
            text: "How are you",
            startTime: 2.0,
            endTime: 4.0,
            confidence: 0.9,
            language: "en-US",
            isFinal: true
        )
        mock.simulateResult(second)
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
        mock.simulateResult(finalResult)
        try await waitForCondition { vm.segments.count == 1 }

        let partial = TranscriptResult(
            text: "Next words",
            startTime: 2.0,
            endTime: 3.0,
            confidence: 0.8,
            language: "en-US",
            isFinal: false
        )
        mock.simulateResult(partial)
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
        mock.simulateResult(partial)
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
        mock.simulateResult(final1)
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
        mock.simulateResult(final2)
        try await waitForCondition { vm.segments.count == 2 }

        #expect(vm.segments.count == 2)
        #expect(vm.segments[1].text == "Second sentence")
    }
}
