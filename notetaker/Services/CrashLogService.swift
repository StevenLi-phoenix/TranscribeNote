import Foundation
import MetricKit
import os

/// Receives crash diagnostics from MetricKit (delivered on next launch after a crash).
nonisolated final class CrashLogService: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "CrashLog")
    private static let shared = CrashLogService()

    private static var crashLogDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("notetaker/CrashLogs", isDirectory: true)
    }

    private static var crashLogFile: URL {
        crashLogDirectory.appendingPathComponent("last_crash.log")
    }

    private override init() {
        super.init()
    }

    /// Register the MetricKit subscriber and check for previous crash logs.
    static func install() {
        checkPreviousCrash()
        MXMetricManager.shared.add(shared)
        logger.info("MetricKit crash diagnostic subscriber installed")
    }

    /// Remove the MetricKit subscriber (for testing).
    static func uninstall() {
        MXMetricManager.shared.remove(shared)
        logger.info("MetricKit crash diagnostic subscriber removed")
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Self.logger.info("Received \(payloads.count) diagnostic payload(s)")

        for payload in payloads {
            if let crashDiagnostics = payload.crashDiagnostics {
                for diagnostic in crashDiagnostics {
                    let report = Self.formatCrashDiagnostic(diagnostic)
                    Self.logger.warning("Crash diagnostic:\n\(report)")
                    Self.writeCrashLog(report)
                }
            }
        }
    }

    // MARK: - Private

    private static func formatCrashDiagnostic(_ diagnostic: MXCrashDiagnostic) -> String {
        var lines: [String] = []
        lines.append("=== MetricKit Crash Diagnostic ===")
        lines.append("Date: \(Date())")

        if let terminationReason = diagnostic.terminationReason {
            lines.append("Termination Reason: \(terminationReason)")
        }
        if let exceptionType = diagnostic.exceptionType {
            lines.append("Exception Type: \(exceptionType)")
        }
        if let exceptionCode = diagnostic.exceptionCode {
            lines.append("Exception Code: \(exceptionCode)")
        }
        if let signal = diagnostic.signal {
            lines.append("Signal: \(signal)")
        }
        if let vmRegionInfo = diagnostic.virtualMemoryRegionInfo {
            lines.append("VM Region Info: \(vmRegionInfo)")
        }

        if let jsonData = diagnostic.callStackTree.jsonRepresentation() as Data?,
           let jsonString = String(data: jsonData, encoding: .utf8) {
            lines.append("Call Stack:\n\(jsonString)")
        }

        return lines.joined(separator: "\n")
    }

    private static func writeCrashLog(_ content: String) {
        try? FileManager.default.createDirectory(at: crashLogDirectory, withIntermediateDirectories: true)
        try? content.write(to: crashLogFile, atomically: true, encoding: .utf8)
    }

    private static func checkPreviousCrash() {
        let file = crashLogFile
        guard FileManager.default.fileExists(atPath: file.path) else { return }

        do {
            let content = try String(contentsOf: file, encoding: .utf8)
            logger.warning("Previous crash detected:\n\(content)")
            try FileManager.default.removeItem(at: file)
        } catch {
            logger.error("Failed to read/clean crash log: \(error.localizedDescription)")
        }
    }
}
