import Testing
import Foundation
import AVFoundation

@Suite("FileAudioSource", .serialized)
struct FileAudioSourceTests {

    @Test(.timeLimit(.minutes(1)))
    func fileAudioSourceDeliversBuffers() async throws {
        let source = FileAudioSource()
        let url = try sampleSpeechURL()

        let finished = LockIsolated(false)

        source.onFinished = {
            finished.setValue(true)
        }

        try source.start(url: url)

        try await waitForCondition(timeout: 10.0) {
            finished.value
        }

        source.stop()
        #expect(source.bufferCount > 0, "Should have delivered at least one buffer")
    }

    @Test(.timeLimit(.minutes(1)))
    func fileAudioSourceCallsOnFinished() async throws {
        let source = FileAudioSource()
        let url = try sampleSpeechURL()

        let finished = LockIsolated(false)
        source.onFinished = {
            finished.setValue(true)
        }

        try source.start(url: url)

        try await waitForCondition(timeout: 10.0) {
            finished.value
        }

        source.stop()
        #expect(finished.value, "onFinished should have been called")
    }

    @Test func stopCleansUpWithoutCrash() async throws {
        let source = FileAudioSource()
        let url = try sampleSpeechURL()

        try source.start(url: url)
        // Brief pause to let engine start
        try await Task.sleep(for: .milliseconds(100))
        source.stop()
        // No crash = success
    }

    @Test(.timeLimit(.minutes(1)))
    func buffersHaveValidFormat() async throws {
        let source = FileAudioSource()
        let url = try sampleSpeechURL()

        let validFormat = LockIsolated(false)
        let finished = LockIsolated(false)

        source.onAudioBuffer = { buffer in
            if buffer.format.sampleRate > 0 && buffer.format.channelCount > 0 {
                validFormat.setValue(true)
            }
        }
        source.onFinished = {
            finished.setValue(true)
        }

        try source.start(url: url)

        try await waitForCondition(timeout: 10.0) {
            finished.value
        }

        source.stop()
        #expect(validFormat.value, "Buffers should have valid format (sampleRate > 0, channelCount > 0)")
    }
}
