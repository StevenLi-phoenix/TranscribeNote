import Testing
@testable import notetaker

@Suite("CrashLogService")
struct CrashLogServiceTests {

    @Test
    func installDoesNotCrash() {
        CrashLogService.install()
    }
}
