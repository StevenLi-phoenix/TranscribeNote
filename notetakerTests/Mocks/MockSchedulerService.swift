import Foundation
@testable import notetaker

/// Mock SchedulerService for testing SchedulerViewModel without real notifications.
final class MockSchedulerService: SchedulerServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _scheduledRecordingIDs: [UUID] = []
    var scheduledRecordingIDs: [UUID] { lock.withLock { _scheduledRecordingIDs } }

    private var _cancelledRecordingIDs: [UUID] = []
    var cancelledRecordingIDs: [UUID] { lock.withLock { _cancelledRecordingIDs } }

    private var _cancelAllCallCount = 0
    var cancelAllCallCount: Int { lock.withLock { _cancelAllCallCount } }

    private var _scheduleCallCount = 0
    var scheduleCallCount: Int { lock.withLock { _scheduleCallCount } }

    func schedule(_ recording: ScheduledRecording) {
        lock.withLock {
            _scheduledRecordingIDs.append(recording.id)
            _scheduleCallCount += 1
        }
    }

    func cancel(_ recording: ScheduledRecording) {
        lock.withLock {
            _cancelledRecordingIDs.append(recording.id)
        }
    }

    func cancelAll() {
        lock.withLock {
            _cancelAllCallCount += 1
        }
    }

    func requestAuthorization() async -> Bool {
        true
    }
}
