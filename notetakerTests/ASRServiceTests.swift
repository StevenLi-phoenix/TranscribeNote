import Testing
import Foundation
import AVFoundation
@testable import notetaker

struct ASRServiceTests {
    @Test func mockEngineStartStop() async throws {
        let engine = MockASREngine()
        #expect(engine.isRecognizing == false)
        #expect(engine.startCallCount == 0)

        let audioEngine = AVAudioEngine()
        try engine.startRecognition(audioEngine: audioEngine)
        #expect(engine.isRecognizing == true)
        #expect(engine.startCallCount == 1)

        await engine.stopRecognition()
        #expect(engine.isRecognizing == false)
        #expect(engine.stopCallCount == 1)
    }

    @Test func mockEngineThrowsOnStart() {
        let engine = MockASREngine()
        engine.shouldThrowOnStart = true

        let audioEngine = AVAudioEngine()
        #expect(throws: MockASREngine.MockError.self) {
            try engine.startRecognition(audioEngine: audioEngine)
        }
        #expect(engine.isRecognizing == false)
    }

    @Test func mockEngineResultCallback() async {
        let engine = MockASREngine()
        var receivedResult: TranscriptResult?

        engine.onResult = { result in
            receivedResult = result
        }

        let result = TranscriptResult(
            text: "Hello world",
            startTime: 0.0,
            endTime: 1.5,
            confidence: 0.95,
            language: "en-US",
            isFinal: true
        )
        await engine.simulateResult(result)

        #expect(receivedResult?.text == "Hello world")
        #expect(receivedResult?.isFinal == true)
        #expect(receivedResult?.confidence == 0.95)
    }

    @Test func mockEngineErrorCallback() {
        let engine = MockASREngine()
        var receivedError: Error?

        engine.onError = { error in
            receivedError = error
        }

        engine.simulateError(MockASREngine.MockError(message: "Test error"))
        #expect(receivedError != nil)
    }

}
