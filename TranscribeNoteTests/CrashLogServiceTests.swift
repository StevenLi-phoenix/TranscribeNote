import Testing
@testable import TranscribeNote

@Suite("CrashLogService")
struct CrashLogServiceTests {

    @Test
    func installDoesNotCrash() {
        CrashLogService.install()
        CrashLogService.uninstall()
    }

    @Test
    func installAndUninstallAreIdempotent() {
        CrashLogService.install()
        CrashLogService.install()
        CrashLogService.uninstall()
        CrashLogService.uninstall()
    }
}
