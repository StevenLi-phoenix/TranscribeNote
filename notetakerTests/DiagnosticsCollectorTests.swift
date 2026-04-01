import Testing
@testable import notetaker

@Suite("DiagnosticsCollector")
struct DiagnosticsCollectorTests {
    @Test func collectHardwareReturnsValidInfo() {
        let hw = DiagnosticsCollector.collectHardware()
        #expect(hw.totalMemoryGB > 0)
        #expect(!hw.processorName.isEmpty)
        #expect(!hw.osVersion.isEmpty)
    }

    @Test func collectStorageReturnsNonNegative() {
        let storage = DiagnosticsCollector.collectStorage()
        #expect(storage.databaseSizeBytes >= 0)
        #expect(storage.audioFilesSizeBytes >= 0)
        #expect(storage.audioFileCount >= 0)
        #expect(storage.totalSizeBytes >= 0)
    }

    @Test func storageTotalIsSum() {
        let storage = DiagnosticsCollector.collectStorage()
        #expect(storage.totalSizeBytes == storage.databaseSizeBytes + storage.audioFilesSizeBytes)
    }

    @Test func collectLLMInfoReturnsValidInfo() {
        let llm = DiagnosticsCollector.collectLLMInfo()
        #expect(!llm.provider.isEmpty)
        #expect(!llm.model.isEmpty)
        // baseURL may be empty for on-device providers (e.g., foundationModels)
    }

    @Test func collectAudioInfoReturnsDefaults() {
        let audio = DiagnosticsCollector.collectAudioInfo()
        #expect(audio.sampleRate > 0)
        #expect(audio.channels > 0)
        #expect(audio.bufferDuration > 0)
    }

    @Test func collectCrashInfoDoesNotCrash() {
        let crash = DiagnosticsCollector.collectCrashInfo()
        // May or may not have a crash log — just verify it doesn't crash
        if crash.hasCrashLog {
            #expect(crash.crashLogContent != nil)
        }
    }

    @Test func exportReportContainsAllSections() {
        let report = DiagnosticsCollector.exportReport()
        #expect(report.contains("Notetaker Diagnostics Report"))
        #expect(report.contains("Hardware"))
        #expect(report.contains("Audio Pipeline"))
        #expect(report.contains("LLM Engine"))
        #expect(report.contains("Storage"))
        #expect(report.contains("Crash Log"))
    }

    @Test func exportReportContainsHardwareDetails() {
        let report = DiagnosticsCollector.exportReport()
        #expect(report.contains("Memory:"))
        #expect(report.contains("Processor:"))
        #expect(report.contains("macOS:"))
        #expect(report.contains("App Version:"))
    }

    @Test func formatBytesReturnsReadableString() {
        let result = DiagnosticsCollector.formatBytes(1024 * 1024)
        #expect(!result.isEmpty)
    }

    @Test func formatBytesZero() {
        let result = DiagnosticsCollector.formatBytes(0)
        #expect(!result.isEmpty)
    }

    @Test func formatSampleRate() {
        let result = DiagnosticsCollector.formatSampleRate(16000)
        #expect(result == "16000 Hz")
    }

    @Test func storageSizeFormatted() {
        let storage = DiagnosticsCollector.StorageInfo(
            databaseSizeBytes: 1024 * 1024 * 5,
            audioFilesSizeBytes: 1024 * 1024 * 100,
            audioFileCount: 10,
            totalSizeBytes: 1024 * 1024 * 105
        )
        #expect(!storage.databaseSizeFormatted.isEmpty)
        #expect(!storage.audioFilesSizeFormatted.isEmpty)
        #expect(!storage.totalSizeFormatted.isEmpty)
    }

    @Test func hardwareInfoMemoryIsReasonable() {
        let hw = DiagnosticsCollector.collectHardware()
        #expect(hw.totalMemoryGB >= 4)
        #expect(hw.totalMemoryGB <= 512)
    }
}
