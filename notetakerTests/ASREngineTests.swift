import Testing
import Foundation
@testable import notetaker

@Suite("ASREngine – Incremental Finalization", .serialized)
struct ASREngineTests {

    /// Verify RecordingViewModel correctly handles incremental finals from MockASREngine.
    @Test
    func viewModelHandlesIncrementalFinals() async throws {
        let mockEngine = MockASREngine()
        let vm = await RecordingViewModel(asrEngine: mockEngine)

        // Simulate incremental final result
        let final1 = TranscriptResult(
            text: "Hello world",
            startTime: 0.0,
            endTime: 1.5,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await mockEngine.simulateResult(final1)

        try await waitForCondition { await vm.segments.count == 1 }

        let segments = await vm.segments
        #expect(segments.count == 1)
        #expect(segments.first?.text == "Hello world")

        // Simulate partial (uncommitted tail)
        let partial = TranscriptResult(
            text: "how are",
            startTime: 1.5,
            endTime: 2.0,
            confidence: 0.0,
            language: "en-US",
            isFinal: false
        )
        await mockEngine.simulateResult(partial)

        try await waitForCondition { await vm.partialText == "how are" }

        let partialText = await vm.partialText
        #expect(partialText == "how are")

        // Simulate second incremental final
        let final2 = TranscriptResult(
            text: "how are you",
            startTime: 1.5,
            endTime: 3.0,
            confidence: 0.90,
            language: "en-US",
            isFinal: true
        )
        await mockEngine.simulateResult(final2)

        try await waitForCondition { await vm.segments.count == 2 }

        let finalSegments = await vm.segments
        #expect(finalSegments.count == 2)
        #expect(finalSegments[1].text == "how are you")

        let finalPartial = await vm.partialText
        #expect(finalPartial == "")
    }

    /// Verify that hypothesis reset (duplicate final text) does not produce duplicate segments.
    @Test
    func hypothesisResetDoesNotDuplicate() async throws {
        let mockEngine = MockASREngine()
        let vm = await RecordingViewModel(asrEngine: mockEngine)

        // Simulate first final commit
        let final1 = TranscriptResult(
            text: "Yes, so",
            startTime: 0.0,
            endTime: 1.5,
            confidence: 0.9,
            language: "en-US",
            isFinal: true
        )
        await mockEngine.simulateResult(final1)
        try await waitForCondition { await vm.segments.count == 1 }

        // Simulate hypothesis reset: Apple re-commits the same text
        let duplicate = TranscriptResult(
            text: "Yes, so",
            startTime: 0.0,
            endTime: 1.5,
            confidence: 0.92,
            language: "en-US",
            isFinal: true
        )
        await mockEngine.simulateResult(duplicate)
        try await Task.sleep(for: .milliseconds(50))

        let segments = await vm.segments
        #expect(segments.count == 1, "Duplicate final should be skipped")

        // Simulate new, different final after reset
        let final2 = TranscriptResult(
            text: "If you want",
            startTime: 1.5,
            endTime: 3.0,
            confidence: 0.88,
            language: "en-US",
            isFinal: true
        )
        await mockEngine.simulateResult(final2)
        try await waitForCondition { await vm.segments.count == 2 }

        let finalSegments = await vm.segments
        #expect(finalSegments.count == 2)
        #expect(finalSegments[0].text == "Yes, so")
        #expect(finalSegments[1].text == "If you want")
    }

    /// Verify that multiple incremental finals accumulate correctly.
    @Test
    func multipleIncrementalFinalsAccumulate() async throws {
        let mockEngine = MockASREngine()
        let vm = await RecordingViewModel(asrEngine: mockEngine)

        let texts = ["One", "Two", "Three"]
        for (i, text) in texts.enumerated() {
            let result = TranscriptResult(
                text: text,
                startTime: Double(i),
                endTime: Double(i) + 0.5,
                confidence: 0.9,
                language: "en-US",
                isFinal: true
            )
            await mockEngine.simulateResult(result)
        }

        try await waitForCondition { await vm.segments.count == 3 }

        let segments = await vm.segments
        #expect(segments.count == 3)
        #expect(segments.map(\.text) == texts)
    }
}
