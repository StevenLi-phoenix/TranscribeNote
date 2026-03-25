import AVFoundation
import os

enum AudioExporter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "AudioExporter")

    /// Merge multiple audio files into a single M4A file at `destination`.
    /// If `urls` has only one element, copies it directly.
    static func mergeAndExport(urls: [URL], to destination: URL) async throws {
        guard !urls.isEmpty else {
            throw AudioExportError.noFiles
        }

        if urls.count == 1 {
            logger.info("Single clip, copying directly")
            try FileManager.default.copyItem(at: urls[0], to: destination)
            return
        }

        logger.info("Merging \(urls.count) clips into \(destination.lastPathComponent)")

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioExportError.compositionFailed
        }

        var insertTime = CMTime.zero
        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)
            let assetDuration = try await asset.load(.duration)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                logger.warning("Clip \(index) has no audio track, skipping: \(url.lastPathComponent)")
                continue
            }
            let timeRange = CMTimeRange(start: .zero, duration: assetDuration)
            try track.insertTimeRange(timeRange, of: assetTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, assetDuration)
            logger.info("Inserted clip \(index) (\(CMTimeGetSeconds(assetDuration))s)")
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioExportError.exportSessionFailed
        }

        exportSession.outputURL = destination
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            logger.info("Export completed: \(destination.lastPathComponent)")
        case .failed:
            let error = exportSession.error
            logger.error("Export failed: \(error?.localizedDescription ?? "unknown")")
            throw AudioExportError.exportFailed(error?.localizedDescription ?? "unknown")
        case .cancelled:
            logger.info("Export cancelled")
            throw CancellationError()
        default:
            throw AudioExportError.exportFailed("Unexpected status: \(exportSession.status.rawValue)")
        }
    }
}

enum AudioExportError: LocalizedError {
    case noFiles
    case compositionFailed
    case exportSessionFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFiles: "No audio files to export"
        case .compositionFailed: "Failed to create audio composition"
        case .exportSessionFailed: "Failed to create export session"
        case .exportFailed(let reason): "Audio export failed: \(reason)"
        }
    }
}
