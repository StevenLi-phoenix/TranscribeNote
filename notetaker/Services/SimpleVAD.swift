import os

/// Voice Activity Detection based on energy threshold.
/// Decides whether to forward audio buffers to ASR or suppress them during silence.
///
/// Thread-safe via `OSAllocatedUnfairLock` — designed to be called from the audio write queue.
nonisolated final class SimpleVAD: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.notetaker", category: "SimpleVAD")

    let silenceThreshold: Float
    let silenceBuffersForSuppress: Int
    let silenceBuffersForTimeout: Int?

    private let lock: OSAllocatedUnfairLock<State>

    private struct State: Sendable {
        var isSpeaking: Bool = true
        var silentBufferCount: Int = 0
        var timeoutFired: Bool = false
    }

    init(
        silenceThreshold: Float,
        silenceBuffersForSuppress: Int,
        silenceBuffersForTimeout: Int?
    ) {
        self.silenceThreshold = silenceThreshold
        self.silenceBuffersForSuppress = silenceBuffersForSuppress
        self.silenceBuffersForTimeout = silenceBuffersForTimeout
        self.lock = OSAllocatedUnfairLock(initialState: State())
    }

    /// Process an audio level (0..1 log-scaled) and return a VAD decision.
    func processLevel(_ level: Float) -> VADDecision {
        let (decision, logEvent) = lock.withLock { state -> (VADDecision, LogEvent?) in
            if level >= silenceThreshold {
                // Speech detected — reset silence counters
                let wasSupressed = !state.isSpeaking
                let count = state.silentBufferCount
                state.isSpeaking = true
                state.silentBufferCount = 0
                state.timeoutFired = false
                let event: LogEvent? = wasSupressed ? .speechResumed(afterBuffers: count) : nil
                return (.forward, event)
            }

            // Silence detected
            state.silentBufferCount += 1
            let count = state.silentBufferCount

            // Check timeout first (fires once per silence period)
            if let timeoutBuffers = silenceBuffersForTimeout,
               count >= timeoutBuffers,
               !state.timeoutFired {
                state.timeoutFired = true
                return (.silenceTimeout, .timeoutReached(buffers: count))
            }

            // Check suppress threshold
            if count >= silenceBuffersForSuppress {
                if state.isSpeaking {
                    state.isSpeaking = false
                    return (.suppress, .suppressStarted(buffers: count))
                }
                return (.suppress, nil)
            }

            // Grace period — still forward to ASR
            return (.forward, nil)
        }

        // Log outside the lock
        if let logEvent {
            switch logEvent {
            case .speechResumed(let buffers):
                Self.logger.debug("Speech resumed after \(buffers) silent buffers")
            case .timeoutReached(let buffers):
                Self.logger.info("Silence timeout reached after \(buffers) buffers")
            case .suppressStarted(let buffers):
                Self.logger.debug("Suppressing ASR after \(buffers) silent buffers")
            }
        }

        return decision
    }

    private enum LogEvent {
        case speechResumed(afterBuffers: Int)
        case timeoutReached(buffers: Int)
        case suppressStarted(buffers: Int)
    }
}

enum VADDecision: Equatable, Sendable {
    case forward
    case suppress
    case silenceTimeout
}
