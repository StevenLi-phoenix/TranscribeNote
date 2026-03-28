import AppKit
import Foundation
import os

/// Lightweight data carrier for auto-export (no SwiftData dependency).
nonisolated struct ExportSessionInfo: Sendable {
    let title: String
    let date: Date
    let duration: TimeInterval
    let segments: [(startTime: TimeInterval, text: String)]
    let overallSummary: String?
}

/// Result of a single export action.
nonisolated struct ExportResult: Sendable {
    let actionID: String
    let success: Bool
    let message: String
}

/// Auto-export pipeline service. Pure logic for formatting; URLSession for webhook.
nonisolated enum AutoExportService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "AutoExportService"
    )

    // MARK: - Pipeline Execution

    static func execute(
        actions: [ExportAction],
        sessionInfo: ExportSessionInfo,
        urlSession: URLSession = .shared
    ) async -> [ExportResult] {
        var results: [ExportResult] = []
        for action in actions {
            let result = await executeAction(action, sessionInfo: sessionInfo, urlSession: urlSession)
            results.append(result)
            logger.info("Auto-export [\(action.id)]: \(result.success ? "success" : "failed") - \(result.message)")
        }
        return results
    }

    private static func executeAction(
        _ action: ExportAction,
        sessionInfo: ExportSessionInfo,
        urlSession: URLSession
    ) async -> ExportResult {
        switch action {
        case .writeFile(let options):
            return writeFile(sessionInfo: sessionInfo, options: options)
        case .copyTranscript:
            return await copyTranscript(sessionInfo: sessionInfo)
        case .webhook(let options):
            return await sendWebhook(sessionInfo: sessionInfo, options: options, urlSession: urlSession)
        }
    }

    // MARK: - Format Helpers

    /// Format session as plain text for file export.
    static func formatAsText(sessionInfo: ExportSessionInfo) -> String {
        var lines: [String] = []
        lines.append("# \(sessionInfo.title)")
        lines.append("Date: \(formatDate(sessionInfo.date))")
        lines.append("Duration: \(formatDuration(sessionInfo.duration))")
        lines.append("")

        if let summary = sessionInfo.overallSummary, !summary.isEmpty {
            lines.append("## Summary")
            lines.append(summary)
            lines.append("")
        }

        if !sessionInfo.segments.isEmpty {
            lines.append("## Transcript")
            for seg in sessionInfo.segments {
                let ts = formatTimestamp(seg.startTime)
                lines.append("\(ts)  \(seg.text)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Format timestamp as MM:SS.
    static func formatTimestamp(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Format date as yyyy-MM-dd.
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Format duration as "Xm Ys".
    static func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    /// Interpolate filename template with session metadata.
    static func interpolateFilename(template: String, title: String, date: Date) -> String {
        var result = template
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        result = result.replacingOccurrences(of: "{{title}}", with: safeTitle)
        result = result.replacingOccurrences(of: "{{date}}", with: formatDate(date))
        return result
    }

    // MARK: - Actions

    private static func writeFile(sessionInfo: ExportSessionInfo, options: WriteFileOptions) -> ExportResult {
        guard !options.directoryPath.isEmpty else {
            return ExportResult(actionID: "writeFile", success: false, message: "No directory configured")
        }

        let filename = interpolateFilename(
            template: options.filenameTemplate,
            title: sessionInfo.title,
            date: sessionInfo.date
        )
        let url = URL(fileURLWithPath: options.directoryPath).appendingPathComponent("\(filename).md")
        let content = formatAsText(sessionInfo: sessionInfo)

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ExportResult(actionID: "writeFile", success: true, message: url.lastPathComponent)
        } catch {
            return ExportResult(actionID: "writeFile", success: false, message: error.localizedDescription)
        }
    }

    @MainActor
    private static func copyTranscript(sessionInfo: ExportSessionInfo) -> ExportResult {
        let text = formatAsText(sessionInfo: sessionInfo)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return ExportResult(actionID: "copyTranscript", success: true, message: "\(text.count) chars copied")
    }

    private static func sendWebhook(
        sessionInfo: ExportSessionInfo,
        options: WebhookOptions,
        urlSession: URLSession
    ) async -> ExportResult {
        guard let url = URL(string: options.url), !options.url.isEmpty else {
            return ExportResult(actionID: "webhook", success: false, message: "Invalid webhook URL")
        }

        var payload: [String: Any] = [
            "title": sessionInfo.title,
            "date": ISO8601DateFormatter().string(from: sessionInfo.date),
            "duration": sessionInfo.duration,
        ]

        if options.includeTranscript {
            payload["transcript"] = sessionInfo.segments.map { [
                "text": $0.text,
                "startTime": $0.startTime,
            ] as [String: Any] }
        }

        if options.includeSummary, let summary = sessionInfo.overallSummary {
            payload["summary"] = summary
        }

        var request = URLRequest(url: url)
        request.httpMethod = options.method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !options.secretHeader.isEmpty {
            request.setValue(options.secretHeader, forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await urlSession.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return ExportResult(actionID: "webhook", success: true, message: "HTTP \(http.statusCode)")
            } else if let http = response as? HTTPURLResponse {
                return ExportResult(actionID: "webhook", success: false, message: "HTTP \(http.statusCode)")
            }
            return ExportResult(actionID: "webhook", success: true, message: "Sent")
        } catch {
            return ExportResult(actionID: "webhook", success: false, message: error.localizedDescription)
        }
    }
}
