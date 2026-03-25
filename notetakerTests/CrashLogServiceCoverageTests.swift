import Testing
import Foundation
@testable import notetaker

/// Extended coverage tests for CrashLogService file system operations.
///
/// These tests exercise the crash log read/write/clear lifecycle by placing
/// files at the known crash log path and invoking `install()` which internally
/// calls `checkPreviousCrash()`. Since `writeCrashLog`, `crashLogDirectory`,
/// and `crashLogFile` are private, we replicate the known path logic and
/// verify observable side-effects.
@Suite("CrashLogService Coverage Tests", .serialized)
struct CrashLogServiceCoverageTests {

    // MARK: - Helpers

    /// Crash log directory matching CrashLogService's private `crashLogDirectory`.
    private var crashLogDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("notetaker/CrashLogs", isDirectory: true)
    }

    /// Crash log file matching CrashLogService's private `crashLogFile`.
    private var crashLogFile: URL {
        crashLogDirectory.appendingPathComponent("last_crash.log")
    }

    /// Remove crash log file and directory to ensure a clean slate.
    private func cleanUp() {
        try? FileManager.default.removeItem(at: crashLogFile)
        // Leave the directory — other tests or the app may need it.
    }

    /// Write a fake crash log with the given content.
    private func writeFakeCrashLog(_ content: String) throws {
        try FileManager.default.createDirectory(
            at: crashLogDirectory,
            withIntermediateDirectories: true
        )
        try content.write(to: crashLogFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Path verification

    @Test("crashLogDirectory lives under Application Support/notetaker/CrashLogs")
    func crashLogDirectoryPath() {
        let path = crashLogDirectory.path
        #expect(path.contains("Application Support/notetaker/CrashLogs"))
    }

    @Test("crashLogFile is last_crash.log inside the crash log directory")
    func crashLogFilePath() {
        let file = crashLogFile
        #expect(file.lastPathComponent == "last_crash.log")
        #expect(file.deletingLastPathComponent() == crashLogDirectory)
    }

    // MARK: - checkPreviousCrash (via install) — no file

    @Test("install succeeds when no crash log file exists")
    func checkPreviousCrashNoCrashLogFile() {
        cleanUp()
        // No crash log on disk — install should complete without error.
        CrashLogService.install()
        CrashLogService.uninstall()

        // The file should still not exist.
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }

    // MARK: - checkPreviousCrash (via install) — file present

    @Test("install reads and removes an existing crash log file")
    func checkPreviousCrashWithCrashLogFile() throws {
        cleanUp()
        let content = "=== MetricKit Crash Diagnostic ===\nSignal: 11\nTest content"
        try writeFakeCrashLog(content)

        // Verify file was written.
        #expect(FileManager.default.fileExists(atPath: crashLogFile.path))

        // install() calls checkPreviousCrash() which reads then removes.
        CrashLogService.install()
        CrashLogService.uninstall()

        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }

    @Test("install handles empty crash log file gracefully")
    func checkPreviousCrashWithEmptyFile() throws {
        cleanUp()
        try writeFakeCrashLog("")

        #expect(FileManager.default.fileExists(atPath: crashLogFile.path))

        CrashLogService.install()
        CrashLogService.uninstall()

        // Empty file should still be removed.
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }

    @Test("install handles large crash log content")
    func checkPreviousCrashWithLargeContent() throws {
        cleanUp()
        // Simulate a large crash report (~100 KB).
        let largeContent = String(repeating: "Stack frame 0x00007fff12345678\n", count: 3000)
        try writeFakeCrashLog(largeContent)

        let attrs = try FileManager.default.attributesOfItem(atPath: crashLogFile.path)
        let fileSize = attrs[.size] as? Int ?? 0
        #expect(fileSize > 50_000, "Expected a large crash log file")

        CrashLogService.install()
        CrashLogService.uninstall()

        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }

    @Test("install handles crash log with unicode content")
    func checkPreviousCrashWithUnicodeContent() throws {
        cleanUp()
        let unicodeContent = "=== Crash ===\nReason: 意外终止\nEmoji: 💥\nPath: /usr/lib/libsystem_c.dylib"
        try writeFakeCrashLog(unicodeContent)

        CrashLogService.install()
        CrashLogService.uninstall()

        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }

    // MARK: - clearCrashLog (via consecutive installs)

    @Test("consecutive installs clear crash log only once")
    func consecutiveInstallsClearOnce() throws {
        cleanUp()
        try writeFakeCrashLog("crash data")

        // First install reads and removes.
        CrashLogService.install()
        CrashLogService.uninstall()
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))

        // Second install with no file — should be a no-op.
        CrashLogService.install()
        CrashLogService.uninstall()
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }

    // MARK: - File system round-trip

    @Test("write then install reads and removes — full lifecycle")
    func fullFileSystemLifecycle() throws {
        cleanUp()

        // Step 1: No file exists.
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))

        // Step 2: Write a crash log.
        let content = "=== MetricKit Crash Diagnostic ===\nException Type: 6\nSignal: 11"
        try writeFakeCrashLog(content)
        #expect(FileManager.default.fileExists(atPath: crashLogFile.path))

        // Step 3: Verify content was written correctly.
        let readBack = try String(contentsOf: crashLogFile, encoding: .utf8)
        #expect(readBack == content)

        // Step 4: install() should read and remove.
        CrashLogService.install()
        CrashLogService.uninstall()
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))

        // Step 5: Another install with no file is safe.
        CrashLogService.install()
        CrashLogService.uninstall()
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }

    @Test("crash log directory is created if it does not exist")
    func directoryCreatedOnWrite() throws {
        // Remove entire directory.
        try? FileManager.default.removeItem(at: crashLogDirectory)
        #expect(!FileManager.default.fileExists(atPath: crashLogDirectory.path))

        // Writing a crash log should create the directory.
        try writeFakeCrashLog("test")
        #expect(FileManager.default.fileExists(atPath: crashLogDirectory.path))
        #expect(FileManager.default.fileExists(atPath: crashLogFile.path))

        // Clean up via install.
        CrashLogService.install()
        CrashLogService.uninstall()
    }

    @Test("crash log directory is not removed when crash log file is cleared")
    func directoryPersistsAfterClear() throws {
        cleanUp()
        try writeFakeCrashLog("to be removed")

        CrashLogService.install()
        CrashLogService.uninstall()

        // File removed but directory should still exist.
        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
        #expect(FileManager.default.fileExists(atPath: crashLogDirectory.path))
    }

    // MARK: - Multiline crash report format

    @Test("install handles realistic multi-line crash diagnostic format")
    func realisticCrashDiagnosticFormat() throws {
        cleanUp()
        let report = """
        === MetricKit Crash Diagnostic ===
        Date: 2026-03-24 10:00:00 +0000
        Termination Reason: Namespace SIGNAL, Code 11
        Exception Type: 6
        Exception Code: 0
        Signal: 11
        VM Region Info: 0x0-0x100000000
        Call Stack:
        {"callStacks":[{"threadAttributed":true,"callStackRootFrames":[{"address":4295032832}]}]}
        """
        try writeFakeCrashLog(report)

        CrashLogService.install()
        CrashLogService.uninstall()

        #expect(!FileManager.default.fileExists(atPath: crashLogFile.path))
    }
}
