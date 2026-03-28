import SwiftUI
import UniformTypeIdentifiers
import os

/// Data for rendering a summary card image.
nonisolated struct SummaryCardData: Sendable {
    let title: String
    let date: Date
    let duration: TimeInterval
    let summaryText: String
    let bulletPoints: [String]
    let style: SummaryCardStyle
}

nonisolated enum SummaryCardStyle: String, CaseIterable, Sendable {
    case light
    case dark
    case gradient
}

/// Exports summary content as beautiful card images.
nonisolated enum SummaryCardExporter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SummaryCardExporter")

    // MARK: - Extract Data

    /// Extract bullet points from markdown-formatted summary text.
    static func extractBulletPoints(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("• ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Extract a plain text summary (strip markdown bullet prefixes, limit length).
    static func extractPlainSummary(from text: String, maxLength: Int = 500) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") {
                    l = String(l.dropFirst(2))
                }
                // Strip markdown headers
                while l.hasPrefix("#") { l = String(l.dropFirst()) }
                return l.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }

        let joined = lines.joined(separator: "\n")
        if joined.count > maxLength {
            return String(joined.prefix(maxLength)) + "\u{2026}"
        }
        return joined
    }

    /// Format duration as "Xm Ys".
    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    // MARK: - Render Image

    /// Render a SummaryCardTemplate to NSImage.
    @MainActor
    static func renderToImage(data: SummaryCardData) -> NSImage? {
        let view = SummaryCardTemplate(data: data)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0  // Retina
        renderer.proposedSize = .init(width: 600, height: nil)

        guard let cgImage = renderer.cgImage else {
            logger.error("Failed to render summary card image")
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
    }

    /// Copy rendered card to clipboard as PNG.
    @MainActor
    static func copyToClipboard(data: SummaryCardData) -> Bool {
        guard let image = renderToImage(data: data) else { return false }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.error("Failed to convert rendered card to PNG")
            return false
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)
        logger.info("Copied summary card to clipboard (\(pngData.count) bytes)")
        return true
    }

    /// Save rendered card to file via NSSavePanel.
    @MainActor
    static func saveToFile(data: SummaryCardData) async -> Bool {
        guard let image = renderToImage(data: data) else { return false }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.error("Failed to convert rendered card to PNG for saving")
            return false
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(data.title.replacingOccurrences(of: "/", with: "-")).png"
        panel.canCreateDirectories = true

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return false }

        do {
            try pngData.write(to: url)
            logger.info("Saved summary card to \(url.lastPathComponent)")
            return true
        } catch {
            logger.error("Failed to save summary card: \(error.localizedDescription)")
            return false
        }
    }
}
