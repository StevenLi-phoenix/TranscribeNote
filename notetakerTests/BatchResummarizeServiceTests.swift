import Testing
@testable import notetaker

@Suite("BatchResummarizeService")
struct BatchResummarizeServiceTests {
    @Test func batchProgressFractionComplete() {
        let progress = BatchResummarizeService.BatchProgress(
            total: 10, completed: 3, failed: 1, currentTitle: "Test"
        )
        #expect(progress.fractionComplete == 0.4)
        #expect(!progress.isFinished)
    }

    @Test func batchProgressFinished() {
        let progress = BatchResummarizeService.BatchProgress(
            total: 5, completed: 4, failed: 1, currentTitle: nil
        )
        #expect(progress.isFinished)
        #expect(progress.fractionComplete == 1.0)
    }

    @Test func batchProgressZeroTotal() {
        let progress = BatchResummarizeService.BatchProgress(
            total: 0, completed: 0, failed: 0, currentTitle: nil
        )
        #expect(progress.fractionComplete == 0)
        #expect(progress.isFinished)
    }

    @Test func batchResultSuccess() {
        let result = BatchResummarizeService.BatchResult(
            total: 5, succeeded: 5, failed: 0, errors: []
        )
        #expect(result.succeeded == 5)
        #expect(result.failed == 0)
        #expect(result.errors.isEmpty)
    }

    @Test func batchResultWithFailures() {
        let result = BatchResummarizeService.BatchResult(
            total: 3, succeeded: 1, failed: 2, errors: ["Session A", "Session B"]
        )
        #expect(result.failed == 2)
        #expect(result.errors.count == 2)
    }

    @Test func batchProgressCurrentTitle() {
        let progress = BatchResummarizeService.BatchProgress(
            total: 10, completed: 5, failed: 0, currentTitle: "Sprint Planning"
        )
        #expect(progress.currentTitle == "Sprint Planning")
    }

    @Test func batchProgressPartialCompletion() {
        let progress = BatchResummarizeService.BatchProgress(
            total: 4, completed: 2, failed: 0, currentTitle: "Meeting"
        )
        #expect(progress.fractionComplete == 0.5)
    }

    @MainActor @Test func serviceInitialState() {
        let service = BatchResummarizeService()
        #expect(!service.isRunning)
    }
}
