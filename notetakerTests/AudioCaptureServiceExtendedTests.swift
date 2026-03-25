import Testing
import Foundation
import AVFoundation
@testable import notetaker

// MARK: - AudioCaptureService Extended Tests

@Suite("AudioCaptureService Extended Tests")
struct AudioCaptureServiceExtendedTests {

    // MARK: - Init & Config

    @Test("Default init uses AudioConfig.default")
    func defaultInit() {
        let service = AudioCaptureService()
        // Service should initialize without crashing with default config
        #expect(service.onAudioBuffer == nil)
        #expect(service.onAudioLevel == nil)
        #expect(service.onSilenceTimeout == nil)
    }

    @Test("Init with custom AudioConfig does not crash")
    func customConfigInit() {
        let config = AudioConfig(sampleRate: 44_100, channels: 2, bufferDurationSeconds: 60)
        let service = AudioCaptureService(config: config)
        #expect(service.onAudioBuffer == nil)
    }

    // MARK: - Callback Properties

    @Test("onAudioBuffer can be set and cleared")
    func onAudioBufferSetAndClear() {
        let service = AudioCaptureService()
        #expect(service.onAudioBuffer == nil)

        var callbackInvoked = false
        service.onAudioBuffer = { @Sendable _ in
            callbackInvoked = true
        }
        // Invoke the stored callback to prove it's the one we set.
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) {
            buffer.frameLength = 1024
            service.onAudioBuffer?(buffer)
            #expect(callbackInvoked)
        }

        // Clear
        service.onAudioBuffer = nil
        #expect(service.onAudioBuffer == nil)
    }

    @Test("onAudioLevel can be set and cleared")
    func onAudioLevelSetAndClear() {
        let service = AudioCaptureService()
        #expect(service.onAudioLevel == nil)

        var receivedLevel: Float = -1
        service.onAudioLevel = { @Sendable level in
            receivedLevel = level
        }
        service.onAudioLevel?(0.75)
        #expect(receivedLevel == 0.75)

        service.onAudioLevel = nil
        #expect(service.onAudioLevel == nil)
    }

    @Test("onSilenceTimeout can be set and cleared")
    func onSilenceTimeoutSetAndClear() {
        let service = AudioCaptureService()
        #expect(service.onSilenceTimeout == nil)

        var timeoutFired = false
        service.onSilenceTimeout = { @Sendable in
            timeoutFired = true
        }
        service.onSilenceTimeout?()
        #expect(timeoutFired)

        service.onSilenceTimeout = nil
        #expect(service.onSilenceTimeout == nil)
    }

    @Test("onAudioBuffer callback replaces previous callback")
    func onAudioBufferReplace() {
        let service = AudioCaptureService()
        var firstCalled = false
        var secondCalled = false

        service.onAudioBuffer = { @Sendable _ in firstCalled = true }
        service.onAudioBuffer = { @Sendable _ in secondCalled = true }

        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512) {
            buffer.frameLength = 512
            service.onAudioBuffer?(buffer)
        }

        #expect(!firstCalled)
        #expect(secondCalled)
    }

    // MARK: - configureVAD

    @Test("configureVAD with SimpleVAD does not crash")
    func configureVADWithInstance() {
        let service = AudioCaptureService()
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 5,
            silenceBuffersForTimeout: 100
        )
        service.configureVAD(vad)
    }

    @Test("configureVAD with nil does not crash")
    func configureVADWithNil() {
        let service = AudioCaptureService()
        service.configureVAD(nil)
    }

    @Test("configureVAD can replace existing VAD")
    func configureVADReplace() {
        let service = AudioCaptureService()
        let vad1 = SimpleVAD(silenceThreshold: 0.05, silenceBuffersForSuppress: 5, silenceBuffersForTimeout: nil)
        let vad2 = SimpleVAD(silenceThreshold: 0.10, silenceBuffersForSuppress: 10, silenceBuffersForTimeout: 200)

        service.configureVAD(vad1)
        service.configureVAD(vad2)
        service.configureVAD(nil)
    }

    // MARK: - stopCapture without startCapture

    @Test("stopCapture without prior startCapture returns nil and clears callbacks")
    func stopCaptureWithoutStart() {
        let service = AudioCaptureService()
        // Set callbacks to verify they get cleared
        service.onAudioBuffer = { @Sendable _ in }
        service.onAudioLevel = { @Sendable _ in }
        service.onSilenceTimeout = { @Sendable in }
        service.configureVAD(SimpleVAD(silenceThreshold: 0.05, silenceBuffersForSuppress: 3, silenceBuffersForTimeout: nil))

        let url = service.stopCapture()
        #expect(url == nil)

        // Callbacks should be cleared by stopCapture
        #expect(service.onAudioBuffer == nil)
        #expect(service.onAudioLevel == nil)
        #expect(service.onSilenceTimeout == nil)
    }

    @Test("Multiple stopCapture calls without start do not crash")
    func multipleStopCaptureWithoutStart() {
        let service = AudioCaptureService()
        #expect(service.stopCapture() == nil)
        #expect(service.stopCapture() == nil)
        #expect(service.stopCapture() == nil)
    }

    // MARK: - requestPermission

    @Test("requestPermission returns a Bool without crashing")
    func requestPermissionReturnsBool() async {
        let service = AudioCaptureService()
        let granted = await service.requestPermission()
        // In test environment, may return true or false depending on permissions.
        #expect(granted == true || granted == false)
    }

    // MARK: - AudioCaptureError

    @Test("AudioCaptureError.recordingsDirectoryUnavailable is an Error")
    func audioCaptureErrorConformsToError() {
        let error: Error = AudioCaptureService.AudioCaptureError.recordingsDirectoryUnavailable
        #expect(error is AudioCaptureService.AudioCaptureError)
    }

    // MARK: - audioEngine property

    @Test("audioEngine is accessible and not running initially")
    func audioEngineAccessible() {
        let service = AudioCaptureService()
        let engine = service.audioEngine
        #expect(!engine.isRunning)
    }

    // MARK: - Concurrent callback access

    @Test("Concurrent callback set/get does not crash")
    func concurrentCallbackAccess() async {
        let service = AudioCaptureService()

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    if i % 3 == 0 {
                        service.onAudioBuffer = { @Sendable _ in }
                    } else if i % 3 == 1 {
                        service.onAudioLevel = { @Sendable _ in }
                    } else {
                        service.onSilenceTimeout = { @Sendable in }
                    }
                }
            }
            // Readers
            for i in 0..<50 {
                group.addTask {
                    if i % 3 == 0 {
                        _ = service.onAudioBuffer
                    } else if i % 3 == 1 {
                        _ = service.onAudioLevel
                    } else {
                        _ = service.onSilenceTimeout
                    }
                }
            }
            // VAD config changes
            for _ in 0..<20 {
                group.addTask {
                    service.configureVAD(
                        SimpleVAD(silenceThreshold: 0.05, silenceBuffersForSuppress: 5, silenceBuffersForTimeout: nil)
                    )
                }
            }
        }
    }

    @Test("Concurrent stopCapture calls do not crash")
    func concurrentStopCapture() async {
        let service = AudioCaptureService()
        service.onAudioBuffer = { @Sendable _ in }
        service.onAudioLevel = { @Sendable _ in }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = service.stopCapture()
                }
            }
        }
    }
}

// MARK: - AudioConfig Extended Tests (non-overlapping with AudioConfigTests)

@Suite("AudioConfig Extended Tests")
struct AudioConfigExtendedTests {

    @Test("bufferCapacity with high sample rate")
    func bufferCapacityHighSampleRate() {
        let config = AudioConfig(sampleRate: 96_000, channels: 1, bufferDurationSeconds: 10)
        #expect(config.bufferCapacity == 960_000)
    }

    @Test("AudioConfig is Sendable across concurrency boundaries")
    func sendableConformance() async {
        let config = AudioConfig(sampleRate: 16_000, channels: 1, bufferDurationSeconds: 30)
        let result = await Task.detached {
            return config.sampleRate
        }.value
        #expect(result == 16_000)
    }

    @Test("Multiple AudioConfig instances are independent")
    func multipleInstances() {
        let config1 = AudioConfig(sampleRate: 16_000, channels: 1, bufferDurationSeconds: 30)
        let config2 = AudioConfig(sampleRate: 44_100, channels: 2, bufferDurationSeconds: 60)

        #expect(config1.sampleRate != config2.sampleRate)
        #expect(config1.channels != config2.channels)
        #expect(config1.bufferCapacity != config2.bufferCapacity)
    }

    @Test("bufferCapacity scales linearly with duration")
    func bufferCapacityLinearScaling() {
        let config1 = AudioConfig(sampleRate: 16_000, channels: 1, bufferDurationSeconds: 10)
        let config2 = AudioConfig(sampleRate: 16_000, channels: 1, bufferDurationSeconds: 20)
        #expect(config2.bufferCapacity == config1.bufferCapacity * 2)
    }

    @Test("bufferCapacity with minimal 1 second duration")
    func bufferCapacityOneSecond() {
        let config = AudioConfig(sampleRate: 8_000, channels: 1, bufferDurationSeconds: 1)
        #expect(config.bufferCapacity == 8_000)
    }
}

// MARK: - SimpleVAD Extended Tests

@Suite("SimpleVAD Extended Tests")
struct SimpleVADExtendedTests {

    @Test("Exact threshold level counts as speech (>=)")
    func exactThresholdIsSpeech() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: nil
        )
        let decision = vad.processLevel(0.05)
        #expect(decision == .forward)
    }

    @Test("Level just below threshold counts as silence")
    func justBelowThresholdIsSilence() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 1,
            silenceBuffersForTimeout: nil
        )
        let decision = vad.processLevel(0.04999)
        #expect(decision == .suppress)
    }

    @Test("Zero level is silence")
    func zeroLevelIsSilence() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 1,
            silenceBuffersForTimeout: nil
        )
        #expect(vad.processLevel(0.0) == .suppress)
    }

    @Test("Max level (1.0) is speech")
    func maxLevelIsSpeech() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: nil
        )
        #expect(vad.processLevel(1.0) == .forward)
    }

    @Test("Suppress threshold of 1 means first silent buffer suppresses immediately")
    func suppressThresholdOne() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 1,
            silenceBuffersForTimeout: nil
        )
        #expect(vad.processLevel(0.01) == .suppress)
    }

    @Test("Timeout equals suppress threshold fires timeout on that buffer")
    func timeoutEqualsSuppressThreshold() {
        // suppress at 3, timeout at 3 -- timeout checked first
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: 3
        )
        #expect(vad.processLevel(0.01) == .forward)
        #expect(vad.processLevel(0.01) == .forward)
        #expect(vad.processLevel(0.01) == .silenceTimeout)
    }

    @Test("Timeout at buffer 1 fires immediately on first silent buffer")
    func timeoutAtOne() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 5,
            silenceBuffersForTimeout: 1
        )
        #expect(vad.processLevel(0.01) == .silenceTimeout)
        // Subsequent: not yet at suppress threshold (only 2 buffers, need 5)
        #expect(vad.processLevel(0.01) == .forward)
    }

    @Test("Alternating speech and silence resets counters each time")
    func alternatingSpeechSilence() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: nil
        )
        for _ in 0..<10 {
            #expect(vad.processLevel(0.01) == .forward) // silent buffer 1
            #expect(vad.processLevel(0.01) == .forward) // silent buffer 2
            #expect(vad.processLevel(0.1) == .forward)  // speech resets
        }
    }

    @Test("Many speech buffers in a row all return .forward")
    func continuousSpeech() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: 10
        )
        for _ in 0..<100 {
            #expect(vad.processLevel(0.5) == .forward)
        }
    }

    @Test("Timeout fires exactly once even with suppress threshold lower than timeout")
    func timeoutFiresOnceWithLowerSuppress() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 2,
            silenceBuffersForTimeout: 5
        )
        var decisions: [VADDecision] = []
        for _ in 0..<20 {
            decisions.append(vad.processLevel(0.01))
        }
        #expect(decisions[0] == .forward)
        #expect(decisions[1] == .suppress)
        #expect(decisions[2] == .suppress)
        #expect(decisions[3] == .suppress)
        #expect(decisions[4] == .silenceTimeout)
        for i in 5..<20 {
            #expect(decisions[i] == .suppress, "Buffer \(i+1) should suppress after timeout fired")
        }
    }

    @Test("Speech after timeout resets timeoutFired flag, allowing second timeout")
    func secondTimeoutAfterSpeechResume() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 2,
            silenceBuffersForTimeout: 3
        )
        #expect(vad.processLevel(0.01) == .forward)
        #expect(vad.processLevel(0.01) == .suppress)
        #expect(vad.processLevel(0.01) == .silenceTimeout)

        // Speech resumes
        #expect(vad.processLevel(0.1) == .forward)

        // Second silence period fires timeout again
        #expect(vad.processLevel(0.01) == .forward)
        #expect(vad.processLevel(0.01) == .suppress)
        #expect(vad.processLevel(0.01) == .silenceTimeout)
    }

    @Test("High-volume concurrent access with mixed levels")
    func highVolumeConcurrency() async {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 5,
            silenceBuffersForTimeout: 50
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask {
                    let level: Float = Bool.random() ? 0.01 : 0.5
                    let decision = vad.processLevel(level)
                    #expect(
                        decision == .forward || decision == .suppress || decision == .silenceTimeout
                    )
                }
            }
        }
    }

    @Test("VADDecision values are distinct")
    func vadDecisionDistinct() {
        // Use local variables to avoid MainActor isolation issues with #expect macro
        let forward = VADDecision.forward
        let suppress = VADDecision.suppress
        let timeout = VADDecision.silenceTimeout

        #expect(forward == .forward)
        #expect(suppress == .suppress)
        #expect(timeout == .silenceTimeout)

        let forwardNotSuppress = (forward != suppress)
        let forwardNotTimeout = (forward != timeout)
        let suppressNotTimeout = (suppress != timeout)
        #expect(forwardNotSuppress)
        #expect(forwardNotTimeout)
        #expect(suppressNotTimeout)
    }

    @Test("Public properties are accessible")
    func publicProperties() {
        let vad = SimpleVAD(
            silenceThreshold: 0.07,
            silenceBuffersForSuppress: 10,
            silenceBuffersForTimeout: 200
        )
        #expect(vad.silenceThreshold == 0.07)
        #expect(vad.silenceBuffersForSuppress == 10)
        #expect(vad.silenceBuffersForTimeout == 200)
    }

    @Test("Nil timeout property is accessible")
    func nilTimeoutProperty() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 5,
            silenceBuffersForTimeout: nil
        )
        #expect(vad.silenceBuffersForTimeout == nil)
    }

    @Test("Very high silence threshold means most levels are silence")
    func highThreshold() {
        let vad = SimpleVAD(
            silenceThreshold: 0.99,
            silenceBuffersForSuppress: 1,
            silenceBuffersForTimeout: nil
        )
        #expect(vad.processLevel(0.5) == .suppress)
        #expect(vad.processLevel(0.8) == .suppress)
        // At or above threshold is speech
        #expect(vad.processLevel(0.99) == .forward)
        #expect(vad.processLevel(1.0) == .forward)
    }

    @Test("Very low silence threshold means almost everything is speech")
    func lowThreshold() {
        let vad = SimpleVAD(
            silenceThreshold: 0.001,
            silenceBuffersForSuppress: 1,
            silenceBuffersForTimeout: nil
        )
        #expect(vad.processLevel(0.01) == .forward)
        #expect(vad.processLevel(0.0005) == .suppress)
    }
}
