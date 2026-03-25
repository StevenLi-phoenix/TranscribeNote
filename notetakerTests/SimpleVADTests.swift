import Testing
import os
@testable import notetaker

@Suite("SimpleVAD Tests")
struct SimpleVADTests {

    @Test("Level above threshold returns .forward")
    func levelAboveThreshold() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 5,
            silenceBuffersForTimeout: nil
        )
        let decision = vad.processLevel(0.1)
        #expect(decision == .forward)
    }

    @Test("Brief silence within grace period returns .forward")
    func briefSilenceForwards() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 5,
            silenceBuffersForTimeout: nil
        )
        // Feed 4 silent buffers (below suppress threshold of 5)
        for _ in 0..<4 {
            let decision = vad.processLevel(0.01)
            #expect(decision == .forward)
        }
    }

    @Test("Sustained silence returns .suppress")
    func sustainedSilenceSuppresses() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: nil
        )
        // First 2 silent buffers → forward (grace period)
        for _ in 0..<2 {
            #expect(vad.processLevel(0.01) == .forward)
        }
        // 3rd silent buffer → suppress
        #expect(vad.processLevel(0.01) == .suppress)
        // Further silence → still suppress
        #expect(vad.processLevel(0.01) == .suppress)
    }

    @Test("Speech resumes after silence resets counters")
    func speechResumesAfterSilence() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: nil
        )
        // Enter suppress state
        for _ in 0..<5 {
            _ = vad.processLevel(0.01)
        }
        #expect(vad.processLevel(0.01) == .suppress)

        // Speech resumes
        #expect(vad.processLevel(0.1) == .forward)

        // Brief silence again → should forward (counters reset)
        #expect(vad.processLevel(0.01) == .forward)
        #expect(vad.processLevel(0.01) == .forward)
    }

    @Test("Silence exceeding timeout returns .silenceTimeout")
    func silenceTimeout() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 3,
            silenceBuffersForTimeout: 10
        )
        // Fill up to timeout
        for i in 0..<10 {
            let decision = vad.processLevel(0.01)
            if i < 2 {
                #expect(decision == .forward, "Buffer \(i) should forward during grace")
            } else if i < 9 {
                #expect(decision == .suppress, "Buffer \(i) should suppress")
            } else {
                #expect(decision == .silenceTimeout, "Buffer \(i) should timeout")
            }
        }
    }

    @Test("silenceTimeout fires only once per silence period")
    func silenceTimeoutFiresOnce() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 2,
            silenceBuffersForTimeout: 5
        )
        var timeoutCount = 0
        for _ in 0..<20 {
            if vad.processLevel(0.01) == .silenceTimeout {
                timeoutCount += 1
            }
        }
        #expect(timeoutCount == 1)
    }

    @Test("silenceTimeout resets after speech resumes, fires again on next silence")
    func silenceTimeoutResetsAfterSpeech() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 2,
            silenceBuffersForTimeout: 5
        )
        // First timeout
        for _ in 0..<10 {
            _ = vad.processLevel(0.01)
        }
        // Speech resumes → resets timeoutFired
        #expect(vad.processLevel(0.1) == .forward)

        // Second silence period → should fire timeout again
        var timeoutCount = 0
        for _ in 0..<10 {
            if vad.processLevel(0.01) == .silenceTimeout {
                timeoutCount += 1
            }
        }
        #expect(timeoutCount == 1)
    }

    @Test("Nil timeout buffers means no silenceTimeout ever")
    func nilTimeoutNeverFires() {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 2,
            silenceBuffersForTimeout: nil
        )
        for _ in 0..<1000 {
            let decision = vad.processLevel(0.01)
            #expect(decision != .silenceTimeout)
        }
    }

    @Test("Concurrent processLevel calls don't crash")
    func concurrentAccess() async {
        let vad = SimpleVAD(
            silenceThreshold: 0.05,
            silenceBuffersForSuppress: 5,
            silenceBuffersForTimeout: 100
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = vad.processLevel(Float.random(in: 0...1))
                }
            }
        }
        // If we get here without crash, the test passes
    }
}
