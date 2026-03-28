import Foundation
import Testing
@testable import notetaker

struct SummaryCardExporterTests {

    // MARK: - extractBulletPoints

    @Test func extractBulletPointsWithDashPrefix() {
        let text = "- First point\n- Second point\n- Third point"
        let result = SummaryCardExporter.extractBulletPoints(from: text)
        #expect(result == ["First point", "Second point", "Third point"])
    }

    @Test func extractBulletPointsWithAsteriskPrefix() {
        let text = "* Alpha\n* Beta"
        let result = SummaryCardExporter.extractBulletPoints(from: text)
        #expect(result == ["Alpha", "Beta"])
    }

    @Test func extractBulletPointsWithBulletPrefix() {
        let text = "• One\n• Two\n• Three"
        let result = SummaryCardExporter.extractBulletPoints(from: text)
        #expect(result == ["One", "Two", "Three"])
    }

    @Test func extractBulletPointsMixedPrefixes() {
        let text = "- Dash item\n* Star item\n• Bullet item"
        let result = SummaryCardExporter.extractBulletPoints(from: text)
        #expect(result == ["Dash item", "Star item", "Bullet item"])
    }

    @Test func extractBulletPointsFiltersEmptyBullets() {
        let text = "- Valid\n-  \n- Also valid\n- "
        let result = SummaryCardExporter.extractBulletPoints(from: text)
        #expect(result == ["Valid", "Also valid"])
    }

    @Test func extractBulletPointsFromEmptyText() {
        let result = SummaryCardExporter.extractBulletPoints(from: "")
        #expect(result.isEmpty)
    }

    @Test func extractBulletPointsIgnoresNonBulletLines() {
        let text = "Header text\n- Bullet one\nPlain text\n- Bullet two"
        let result = SummaryCardExporter.extractBulletPoints(from: text)
        #expect(result == ["Bullet one", "Bullet two"])
    }

    // MARK: - extractPlainSummary

    @Test func extractPlainSummaryStripsBulletPrefixes() {
        let text = "- First\n- Second"
        let result = SummaryCardExporter.extractPlainSummary(from: text)
        #expect(result == "First\nSecond")
    }

    @Test func extractPlainSummaryStripsHeaders() {
        let text = "## Main Title\nSome content\n### Subtitle"
        let result = SummaryCardExporter.extractPlainSummary(from: text)
        #expect(result == "Main Title\nSome content\nSubtitle")
    }

    @Test func extractPlainSummaryTruncatesAtMaxLength() {
        let longText = String(repeating: "word ", count: 200)
        let result = SummaryCardExporter.extractPlainSummary(from: longText, maxLength: 20)
        #expect(result.count == 21) // 20 chars + ellipsis
        #expect(result.hasSuffix("\u{2026}"))
    }

    @Test func extractPlainSummaryFiltersEmptyLines() {
        let text = "Line one\n\n\nLine two"
        let result = SummaryCardExporter.extractPlainSummary(from: text)
        #expect(result == "Line one\nLine two")
    }

    @Test func extractPlainSummaryEmptyInput() {
        let result = SummaryCardExporter.extractPlainSummary(from: "")
        #expect(result.isEmpty)
    }

    // MARK: - formatDuration

    @Test func formatDurationSecondsOnly() {
        let result = SummaryCardExporter.formatDuration(45)
        #expect(result == "45s")
    }

    @Test func formatDurationMinutesAndSeconds() {
        let result = SummaryCardExporter.formatDuration(125)
        #expect(result == "2m 5s")
    }

    @Test func formatDurationZero() {
        let result = SummaryCardExporter.formatDuration(0)
        #expect(result == "0s")
    }

    @Test func formatDurationExactMinutes() {
        let result = SummaryCardExporter.formatDuration(300)
        #expect(result == "5m 0s")
    }

    // MARK: - SummaryCardData

    @Test func summaryCardDataCreation() {
        let date = Date()
        let data = SummaryCardData(
            title: "Test Session",
            date: date,
            duration: 120,
            summaryText: "A summary",
            bulletPoints: ["Point 1", "Point 2"],
            style: .light
        )
        #expect(data.title == "Test Session")
        #expect(data.date == date)
        #expect(data.duration == 120)
        #expect(data.summaryText == "A summary")
        #expect(data.bulletPoints.count == 2)
        #expect(data.style == .light)
    }

    // MARK: - SummaryCardStyle

    @Test func summaryCardStyleAllCasesCount() {
        #expect(SummaryCardStyle.allCases.count == 3)
    }

    @Test func summaryCardStyleRawValues() {
        #expect(SummaryCardStyle.light.rawValue == "light")
        #expect(SummaryCardStyle.dark.rawValue == "dark")
        #expect(SummaryCardStyle.gradient.rawValue == "gradient")
    }
}
