import Testing
import Foundation
@testable import notetaker

@Suite("File-to-ASR Mock Wiring")
struct FileToASRMockTests {

    /// Wiring test: FileAudioSource → MockASREngine.appendAudioBuffer().
    @Test(.timeLimit(.minutes(1)))
    func fileToMockEngineViaFileAudioSource() async throws {
        let mockEngine = MockASREngine()
        let source = FileAudioSource()

        let finished = LockIsolated(false)

        source.onAudioBuffer = { buffer in
            mockEngine.appendAudioBuffer(buffer)
        }
        source.onFinished = {
            finished.setValue(true)
        }

        let url = try sampleSpeechURL()
        try source.start(url: url)

        try await waitForCondition(timeout: 10.0) {
            finished.value
        }

        source.stop()

        #expect(mockEngine.appendedBufferCount > 0, "MockASREngine should have received buffers from FileAudioSource")
    }
}
