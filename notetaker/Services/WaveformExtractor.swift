import AVFoundation
import os

/// Extracts downsampled waveform amplitude data from audio files.
nonisolated enum WaveformExtractor {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "WaveformExtractor")

    /// Normalized waveform amplitude samples with duration info.
    struct WaveformData: Sendable {
        let samples: [Float]       // 0.0...1.0 normalized amplitudes
        let duration: TimeInterval

        static let empty = WaveformData(samples: [], duration: 0)
    }

    /// Extract waveform data from audio file URL, downsampled to target number of samples.
    /// Uses RMS (root-mean-square) for each window to get smooth waveform representation.
    static func extract(from url: URL, targetSamples: Int = 2000) async throws -> WaveformData {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        let sampleRate = format.sampleRate
        let duration = Double(frameCount) / sampleRate

        guard frameCount > 0 else { return .empty }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw WaveformError.bufferCreationFailed
        }
        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw WaveformError.noChannelData
        }

        let actualSamples = min(targetSamples, Int(frameCount))
        let samplesPerWindow = Int(frameCount) / actualSamples
        var rmsValues = [Float]()
        rmsValues.reserveCapacity(actualSamples)
        var maxRMS: Float = 0

        for i in 0..<actualSamples {
            let start = i * samplesPerWindow
            let end = min(start + samplesPerWindow, Int(frameCount))
            var sumSquares: Float = 0
            for j in start..<end {
                let sample = channelData[j]
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(end - start))
            rmsValues.append(rms)
            maxRMS = max(maxRMS, rms)
        }

        let result: [Float]
        if maxRMS > 0 {
            result = rmsValues.map { $0 / maxRMS }
        } else {
            result = rmsValues
        }

        logger.debug("Extracted \(result.count) waveform samples from \(duration, format: .fixed(precision: 1))s audio")
        return WaveformData(samples: result, duration: duration)
    }

    /// Extract waveform from multiple audio clips (pause/resume creates multiple files).
    static func extract(from urls: [URL], targetSamples: Int = 2000) async throws -> WaveformData {
        guard !urls.isEmpty else { return .empty }
        if urls.count == 1 { return try await extract(from: urls[0], targetSamples: targetSamples) }

        var allData: [WaveformData] = []
        var totalDuration: TimeInterval = 0

        for url in urls {
            let data = try await extract(from: url, targetSamples: targetSamples)
            totalDuration += data.duration
            allData.append(data)
        }

        guard totalDuration > 0 else { return .empty }

        var combined = [Float]()
        combined.reserveCapacity(targetSamples)
        for data in allData {
            let proportion = data.duration / totalDuration
            let sampleCount = max(1, Int(Double(targetSamples) * proportion))
            for i in 0..<sampleCount {
                let sourceIdx = min(
                    Int(Double(i) / Double(sampleCount) * Double(data.samples.count)),
                    data.samples.count - 1
                )
                if sourceIdx >= 0, sourceIdx < data.samples.count {
                    combined.append(data.samples[sourceIdx])
                }
            }
        }

        return WaveformData(samples: combined, duration: totalDuration)
    }

    enum WaveformError: Error, LocalizedError {
        case bufferCreationFailed
        case noChannelData

        var errorDescription: String? {
            switch self {
            case .bufferCreationFailed: return "Failed to create audio buffer"
            case .noChannelData: return "No audio channel data available"
            }
        }
    }

    // MARK: - Pure downsampling for testing

    /// Downsample raw float samples to target count using RMS windows. Pure function for testing.
    static func downsample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard !samples.isEmpty, targetCount > 0 else { return [] }
        let count = min(targetCount, samples.count)
        let windowSize = samples.count / count
        guard windowSize > 0 else { return Array(samples.prefix(count)) }

        var rmsValues = [Float]()
        rmsValues.reserveCapacity(count)
        var maxRMS: Float = 0

        for i in 0..<count {
            let start = i * windowSize
            let end = min(start + windowSize, samples.count)
            var sumSquares: Float = 0
            for j in start..<end {
                sumSquares += samples[j] * samples[j]
            }
            let rms = sqrt(sumSquares / Float(end - start))
            rmsValues.append(rms)
            maxRMS = max(maxRMS, rms)
        }

        if maxRMS > 0 {
            return rmsValues.map { $0 / maxRMS }
        } else {
            return rmsValues
        }
    }
}
