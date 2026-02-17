import Testing
import Foundation
@testable import notetaker

@Suite("AudioCaptureService")
struct AudioCaptureServiceTests {

    @Test
    func recordingsDirectoryIsUnderApplicationSupport() throws {
        let dir = try AudioCaptureService.recordingsDirectory()
        #expect(dir.path.contains("Application Support"))
        #expect(dir.path.hasSuffix("notetaker/Recordings"))
    }

    @Test
    func recordingsDirectoryIsConsistentAcrossCalls() throws {
        let dir1 = try AudioCaptureService.recordingsDirectory()
        let dir2 = try AudioCaptureService.recordingsDirectory()
        #expect(dir1 == dir2)
    }

    @Test
    func recordingsDirectoryIsADirectory() throws {
        let dir = try AudioCaptureService.recordingsDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }
}
