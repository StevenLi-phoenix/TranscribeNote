import Foundation
import os

/// Collects system diagnostics for troubleshooting and performance monitoring.
nonisolated enum DiagnosticsCollector {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "DiagnosticsCollector")

    // MARK: - Data Types

    struct HardwareInfo: Sendable {
        let totalMemoryGB: Int
        let processorName: String
        let osVersion: String
        let appVersion: String
        let buildNumber: String
    }

    struct StorageInfo: Sendable {
        let databaseSizeBytes: Int64
        let audioFilesSizeBytes: Int64
        let audioFileCount: Int
        let totalSizeBytes: Int64

        var databaseSizeFormatted: String { formatBytes(databaseSizeBytes) }
        var audioFilesSizeFormatted: String { formatBytes(audioFilesSizeBytes) }
        var totalSizeFormatted: String { formatBytes(totalSizeBytes) }

        private func formatBytes(_ bytes: Int64) -> String {
            DiagnosticsCollector.formatBytes(bytes)
        }
    }

    struct LLMInfo: Sendable {
        let provider: String
        let model: String
        let baseURL: String
        let temperature: Double
        let maxTokens: Int
    }

    struct AudioInfo: Sendable {
        let sampleRate: Double
        let channels: Int
        let bufferDuration: Double
    }

    struct CrashInfo: Sendable {
        let hasCrashLog: Bool
        let crashLogContent: String?
        let crashLogDate: Date?
    }

    // MARK: - Collection

    static func collectHardware() -> HardwareInfo {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Int(totalBytes / (1024 * 1024 * 1024))

        // Get processor name via sysctl
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpuName = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &cpuName, &size, nil, 0)
        let processor = String(cString: cpuName).trimmingCharacters(in: .whitespaces)

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        logger.debug("Hardware: \(totalGB)GB RAM, processor=\(processor.isEmpty ? "Unknown" : processor)")

        return HardwareInfo(
            totalMemoryGB: totalGB,
            processorName: processor.isEmpty ? "Unknown" : processor,
            osVersion: osVersion,
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }

    static func collectStorage() -> StorageInfo {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("notetaker")

        var dbSize: Int64 = 0
        var audioSize: Int64 = 0
        var audioCount = 0

        if let appDir = appSupport {
            // Database files (.store, .store-wal, .store-shm)
            if let contents = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for url in contents {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    if url.lastPathComponent.contains(".store") {
                        dbSize += Int64(size)
                    }
                }
            }

            // Audio files in Recordings subdirectory
            let recordingsDir = appDir.appendingPathComponent("Recordings")
            if let audioFiles = try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for url in audioFiles {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    audioSize += Int64(size)
                    audioCount += 1
                }
            }
        }

        logger.debug("Storage scan: db=\(dbSize), audio=\(audioSize) (\(audioCount) files)")

        return StorageInfo(
            databaseSizeBytes: dbSize,
            audioFilesSizeBytes: audioSize,
            audioFileCount: audioCount,
            totalSizeBytes: dbSize + audioSize
        )
    }

    static func collectLLMInfo() -> LLMInfo {
        let config = LLMProfileStore.resolveConfig(for: .live)
        return LLMInfo(
            provider: config.provider.displayName,
            model: config.model,
            baseURL: config.baseURL,
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )
    }

    static func collectAudioInfo() -> AudioInfo {
        let config = AudioConfig.default
        return AudioInfo(
            sampleRate: config.sampleRate,
            channels: Int(config.channels),
            bufferDuration: Double(config.bufferDurationSeconds)
        )
    }

    static func collectCrashInfo() -> CrashInfo {
        let fm = FileManager.default
        let crashPath = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("notetaker/CrashLogs/last_crash.log")

        guard let path = crashPath, fm.fileExists(atPath: path.path) else {
            return CrashInfo(hasCrashLog: false, crashLogContent: nil, crashLogDate: nil)
        }

        let content = try? String(contentsOf: path, encoding: .utf8)
        let attrs = try? fm.attributesOfItem(atPath: path.path)
        let date = attrs?[.modificationDate] as? Date

        logger.debug("Crash log found: \(content?.utf8.count ?? 0) bytes")

        return CrashInfo(hasCrashLog: true, crashLogContent: content, crashLogDate: date)
    }

    // MARK: - Export

    static func exportReport() -> String {
        let hw = collectHardware()
        let storage = collectStorage()
        let llm = collectLLMInfo()
        let audio = collectAudioInfo()
        let crash = collectCrashInfo()

        var lines = [String]()
        lines.append("=== Notetaker Diagnostics Report ===")
        lines.append("Generated: \(Date().formatted())")
        lines.append("")

        lines.append("--- Hardware ---")
        lines.append("Memory: \(hw.totalMemoryGB) GB")
        lines.append("Processor: \(hw.processorName)")
        lines.append("macOS: \(hw.osVersion)")
        lines.append("App Version: \(hw.appVersion) (\(hw.buildNumber))")
        lines.append("")

        lines.append("--- Audio Pipeline ---")
        lines.append("Sample Rate: \(Int(audio.sampleRate)) Hz")
        lines.append("Channels: \(audio.channels)")
        lines.append("Buffer Duration: \(Int(audio.bufferDuration))s")
        lines.append("")

        lines.append("--- LLM Engine ---")
        lines.append("Provider: \(llm.provider)")
        lines.append("Model: \(llm.model)")
        lines.append("Base URL: \(llm.baseURL)")
        lines.append("Temperature: \(String(format: "%.1f", llm.temperature))")
        lines.append("Max Tokens: \(llm.maxTokens)")
        lines.append("")

        lines.append("--- Storage ---")
        lines.append("Database: \(storage.databaseSizeFormatted)")
        lines.append("Audio Files: \(storage.audioFilesSizeFormatted) (\(storage.audioFileCount) files)")
        lines.append("Total: \(storage.totalSizeFormatted)")
        lines.append("")

        lines.append("--- Crash Log ---")
        lines.append("Has Crash Log: \(crash.hasCrashLog)")
        if let date = crash.crashLogDate {
            lines.append("Last Crash: \(date.formatted())")
        }

        logger.info("Diagnostics report generated (\(lines.count) lines)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Pure formatting helpers for testing

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatSampleRate(_ rate: Double) -> String {
        "\(Int(rate)) Hz"
    }
}
