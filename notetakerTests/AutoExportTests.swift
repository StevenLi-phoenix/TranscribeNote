import Testing
import Foundation
@testable import notetaker

@Suite(.serialized) struct AutoExportTests {

    // MARK: - Helpers

    private func makeSessionInfo(
        title: String = "Test Session",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        duration: TimeInterval = 125,
        segments: [(TimeInterval, String)] = [(0, "Hello"), (65, "World")],
        overallSummary: String? = "A test summary."
    ) -> ExportSessionInfo {
        ExportSessionInfo(
            title: title,
            date: date,
            duration: duration,
            segments: segments.map { (startTime: $0.0, text: $0.1) },
            overallSummary: overallSummary
        )
    }

    // MARK: - formatTimestamp

    @Test func formatTimestamp_zeroSeconds() {
        #expect(AutoExportService.formatTimestamp(0) == "00:00")
    }

    @Test func formatTimestamp_65seconds() {
        #expect(AutoExportService.formatTimestamp(65) == "01:05")
    }

    @Test func formatTimestamp_3661seconds() {
        #expect(AutoExportService.formatTimestamp(3661) == "61:01")
    }

    // MARK: - formatDate

    @Test func formatDate_knownDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = AutoExportService.formatDate(date)
        // 2023-11-14 in UTC (exact date depends on timezone, just check format)
        #expect(result.count == 10)
        #expect(result.contains("-"))
    }

    // MARK: - formatDuration

    @Test func formatDuration_secondsOnly() {
        #expect(AutoExportService.formatDuration(45) == "45s")
    }

    @Test func formatDuration_minutesAndSeconds() {
        #expect(AutoExportService.formatDuration(125) == "2m 5s")
    }

    @Test func formatDuration_zeroSeconds() {
        #expect(AutoExportService.formatDuration(0) == "0s")
    }

    // MARK: - interpolateFilename

    @Test func interpolateFilename_titleAndDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let result = AutoExportService.interpolateFilename(
            template: "{{title}}_{{date}}",
            title: "My Session",
            date: date
        )
        #expect(result.contains("My Session"))
        #expect(result.contains("_"))
        // Date portion should be yyyy-MM-dd format
        let parts = result.split(separator: "_")
        #expect(parts.count == 2)
    }

    @Test func interpolateFilename_sanitizesSpecialChars() {
        let date = Date(timeIntervalSince1970: 0)
        let result = AutoExportService.interpolateFilename(
            template: "{{title}}",
            title: "My/Session:With\\Slashes",
            date: date
        )
        #expect(!result.contains("/"))
        #expect(!result.contains(":"))
        #expect(!result.contains("\\"))
        #expect(result.contains("My-Session-With-Slashes"))
    }

    @Test func interpolateFilename_noPlaceholders() {
        let date = Date(timeIntervalSince1970: 0)
        let result = AutoExportService.interpolateFilename(template: "fixed-name", title: "ignored", date: date)
        #expect(result == "fixed-name")
    }

    // MARK: - formatAsText

    @Test func formatAsText_withSummaryAndSegments() {
        let info = makeSessionInfo()
        let text = AutoExportService.formatAsText(sessionInfo: info)

        #expect(text.contains("# Test Session"))
        #expect(text.contains("## Summary"))
        #expect(text.contains("A test summary."))
        #expect(text.contains("## Transcript"))
        #expect(text.contains("00:00  Hello"))
        #expect(text.contains("01:05  World"))
        #expect(text.contains("Duration: 2m 5s"))
    }

    @Test func formatAsText_withoutSummary() {
        let info = makeSessionInfo(overallSummary: nil)
        let text = AutoExportService.formatAsText(sessionInfo: info)

        #expect(text.contains("# Test Session"))
        #expect(!text.contains("## Summary"))
        #expect(text.contains("## Transcript"))
    }

    @Test func formatAsText_emptySegments() {
        let info = makeSessionInfo(segments: [], overallSummary: nil)
        let text = AutoExportService.formatAsText(sessionInfo: info)

        #expect(text.contains("# Test Session"))
        #expect(!text.contains("## Transcript"))
    }

    // MARK: - AutoExportConfig round-trip

    @Test func configJsonRoundTrip() throws {
        let config = AutoExportConfig(
            isEnabled: true,
            actions: [
                .writeFile(WriteFileOptions(directoryPath: "/tmp", filenameTemplate: "{{title}}")),
                .copyTranscript,
                .webhook(WebhookOptions(url: "https://example.com", method: "POST")),
            ]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AutoExportConfig.self, from: data)

        #expect(decoded == config)
        #expect(decoded.isEnabled == true)
        #expect(decoded.actions.count == 3)
    }

    @Test func configDefaultValues() {
        let config = AutoExportConfig()
        #expect(config.isEnabled == false)
        #expect(config.actions.isEmpty)
    }

    // MARK: - ExportAction properties

    @Test func exportActionDisplayName() {
        #expect(ExportAction.writeFile(WriteFileOptions()).displayName == "Write to File")
        #expect(ExportAction.copyTranscript.displayName == "Copy Transcript")
        #expect(ExportAction.webhook(WebhookOptions()).displayName == "Send Webhook")
    }

    @Test func exportActionIcon() {
        #expect(ExportAction.writeFile(WriteFileOptions()).icon == "doc.text")
        #expect(ExportAction.copyTranscript.icon == "doc.on.clipboard")
        #expect(ExportAction.webhook(WebhookOptions()).icon == "arrow.up.forward.app")
    }

    @Test func exportActionID() {
        #expect(ExportAction.writeFile(WriteFileOptions()).id == "writeFile")
        #expect(ExportAction.copyTranscript.id == "copyTranscript")
        #expect(ExportAction.webhook(WebhookOptions()).id == "webhook")
    }

    // MARK: - Pipeline execution

    @Test func executeWithEmptyActions() async {
        let info = makeSessionInfo()
        let results = await AutoExportService.execute(actions: [], sessionInfo: info)
        #expect(results.isEmpty)
    }

    @Test func writeFileWithEmptyDirectory() async {
        let info = makeSessionInfo()
        let results = await AutoExportService.execute(
            actions: [.writeFile(WriteFileOptions(directoryPath: ""))],
            sessionInfo: info
        )
        #expect(results.count == 1)
        #expect(results[0].success == false)
        #expect(results[0].message == "No directory configured")
    }

    @Test func writeFileToTempDirectory() async throws {
        let tmpDir = NSTemporaryDirectory()
            .appending("autoexport_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let info = makeSessionInfo(title: "Export Test")
        let options = WriteFileOptions(
            directoryPath: tmpDir,
            filenameTemplate: "{{title}}_{{date}}"
        )
        let results = await AutoExportService.execute(
            actions: [.writeFile(options)],
            sessionInfo: info
        )

        #expect(results.count == 1)
        #expect(results[0].success == true)

        // Verify file was written
        let files = try FileManager.default.contentsOfDirectory(atPath: tmpDir)
        #expect(files.count == 1)
        #expect(files[0].hasSuffix(".md"))
        #expect(files[0].contains("Export Test"))
    }

    @Test func webhookWithInvalidURL() async {
        let info = makeSessionInfo()
        let options = WebhookOptions(url: "")
        let results = await AutoExportService.execute(
            actions: [.webhook(options)],
            sessionInfo: info
        )
        #expect(results.count == 1)
        #expect(results[0].success == false)
        #expect(results[0].message == "Invalid webhook URL")
    }

    @Test func webhookWithMockURLSession() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AutoExportMockURLProtocol.self]
        let session = URLSession(configuration: config)

        AutoExportMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let info = makeSessionInfo()
        let options = WebhookOptions(
            url: "https://example.com/webhook",
            method: "POST",
            includeTranscript: true,
            includeSummary: true
        )
        let results = await AutoExportService.execute(
            actions: [.webhook(options)],
            sessionInfo: info,
            urlSession: session
        )

        #expect(results.count == 1)
        #expect(results[0].success == true)
        #expect(results[0].message == "HTTP 200")
    }

    @Test func webhookWithErrorResponse() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AutoExportMockURLProtocol.self]
        let session = URLSession(configuration: config)

        AutoExportMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }

        let info = makeSessionInfo()
        let options = WebhookOptions(url: "https://example.com/webhook")
        let results = await AutoExportService.execute(
            actions: [.webhook(options)],
            sessionInfo: info,
            urlSession: session
        )

        #expect(results.count == 1)
        #expect(results[0].success == false)
        #expect(results[0].message == "HTTP 500")
    }

    @Test func multipleActionsExecuteIndependently() async {
        let info = makeSessionInfo()
        let results = await AutoExportService.execute(
            actions: [
                .writeFile(WriteFileOptions(directoryPath: "")),
                .webhook(WebhookOptions(url: "")),
            ],
            sessionInfo: info
        )

        // Both should fail independently
        #expect(results.count == 2)
        #expect(results[0].success == false)
        #expect(results[1].success == false)
    }
}

// MARK: - Mock URLProtocol (per-suite to avoid shared state)

private final class AutoExportMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
