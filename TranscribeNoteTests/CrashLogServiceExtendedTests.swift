import Testing
import Foundation
@testable import TranscribeNote

@Suite("CrashLogService Extended Tests", .serialized)
struct CrashLogServiceExtendedTests {

    @Test func installAndUninstallDoNotCrash() {
        CrashLogService.install()
        CrashLogService.uninstall()
    }

    @Test func doubleInstallIsSafe() {
        CrashLogService.install()
        CrashLogService.install()
        CrashLogService.uninstall()
    }

    @Test func doubleUninstallIsSafe() {
        CrashLogService.install()
        CrashLogService.uninstall()
        CrashLogService.uninstall()
    }

    @Test func installChecksForPreviousCrash() {
        // Write a fake crash log, then install should pick it up and clean it
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let crashDir = appSupport.appendingPathComponent("TranscribeNote/CrashLogs", isDirectory: true)
        let crashFile = crashDir.appendingPathComponent("last_crash.log")

        try? FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)
        try? "Test crash log content".write(to: crashFile, atomically: true, encoding: .utf8)

        // install() calls checkPreviousCrash() which should read and remove the file
        CrashLogService.install()

        // The crash log should have been removed
        #expect(!FileManager.default.fileExists(atPath: crashFile.path))

        CrashLogService.uninstall()
    }
}
