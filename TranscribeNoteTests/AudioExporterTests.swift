import Testing
import Foundation
@testable import TranscribeNote

@Suite("AudioExporter Tests")
struct AudioExporterTests {

    // MARK: - AudioExportError descriptions

    @Test func noFilesErrorDescription() {
        let error = AudioExportError.noFiles
        #expect(error.errorDescription == "No audio files to export")
    }

    @Test func compositionFailedErrorDescription() {
        let error = AudioExportError.compositionFailed
        #expect(error.errorDescription == "Failed to create audio composition")
    }

    @Test func exportSessionFailedErrorDescription() {
        let error = AudioExportError.exportSessionFailed
        #expect(error.errorDescription == "Failed to create export session")
    }

    @Test func exportFailedErrorDescription() {
        let error = AudioExportError.exportFailed("timeout")
        #expect(error.errorDescription == "Audio export failed: timeout")
    }

    @Test func exportFailedEmptyReason() {
        let error = AudioExportError.exportFailed("")
        #expect(error.errorDescription == "Audio export failed: ")
    }

    // MARK: - mergeAndExport: empty URLs

    @Test func emptyURLsThrowsNoFiles() async {
        await #expect(throws: AudioExportError.self) {
            try await AudioExporter.mergeAndExport(urls: [], to: URL(fileURLWithPath: "/tmp/out.m4a"))
        }
    }

    @Test func emptyURLsThrowsCorrectCase() async {
        do {
            try await AudioExporter.mergeAndExport(urls: [], to: URL(fileURLWithPath: "/tmp/out.m4a"))
            Issue.record("Expected AudioExportError.noFiles to be thrown")
        } catch let error as AudioExportError {
            switch error {
            case .noFiles:
                break // expected
            default:
                Issue.record("Expected .noFiles but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - mergeAndExport: single file copy

    @Test func singleFileCopiedToDestination() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioExporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceURL = tmpDir.appendingPathComponent("source.m4a")
        let destinationURL = tmpDir.appendingPathComponent("output.m4a")

        let testData = Data("fake audio content".utf8)
        try testData.write(to: sourceURL)

        try await AudioExporter.mergeAndExport(urls: [sourceURL], to: destinationURL)

        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
        let copiedData = try Data(contentsOf: destinationURL)
        #expect(copiedData == testData)
    }

    @Test func singleFileCopyPreservesSource() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioExporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceURL = tmpDir.appendingPathComponent("source.m4a")
        let destinationURL = tmpDir.appendingPathComponent("output.m4a")

        let testData = Data("preserve source test".utf8)
        try testData.write(to: sourceURL)

        try await AudioExporter.mergeAndExport(urls: [sourceURL], to: destinationURL)

        // Source file should still exist (copy, not move)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test func singleFileNonExistentSourceThrows() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioExporterTests-\(UUID().uuidString)")
        let nonExistentURL = tmpDir.appendingPathComponent("does_not_exist.m4a")
        let destinationURL = tmpDir.appendingPathComponent("output.m4a")

        await #expect(throws: (any Error).self) {
            try await AudioExporter.mergeAndExport(urls: [nonExistentURL], to: destinationURL)
        }
    }

    @Test func singleFileDestinationAlreadyExistsThrows() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioExporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceURL = tmpDir.appendingPathComponent("source.m4a")
        let destinationURL = tmpDir.appendingPathComponent("output.m4a")

        try Data("source".utf8).write(to: sourceURL)
        try Data("existing".utf8).write(to: destinationURL)

        // copyItem throws if destination already exists
        await #expect(throws: (any Error).self) {
            try await AudioExporter.mergeAndExport(urls: [sourceURL], to: destinationURL)
        }
    }
}
