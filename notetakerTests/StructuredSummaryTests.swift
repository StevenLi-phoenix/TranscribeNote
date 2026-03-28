import Testing
import Foundation
@testable import notetaker

struct StructuredSummaryTests {

    // MARK: - Codable round-trip

    @Test func codableRoundTrip() throws {
        let original = StructuredSummary(
            summary: "Meeting discussed Q1 goals.",
            keyPoints: ["Revenue up 20%", "New hire plan"],
            actionItems: ["Send report", "Schedule follow-up"],
            sentiment: "positive"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StructuredSummary.self, from: data)
        #expect(decoded == original)
    }

    @Test func toJSONAndFromJSON() {
        let original = StructuredSummary(
            summary: "Test summary",
            keyPoints: ["Point 1"],
            actionItems: [],
            sentiment: "neutral"
        )
        let json = original.toJSON()
        #expect(json != nil)

        let restored = StructuredSummary.fromJSON(json!)
        #expect(restored == original)
    }

    @Test func fromJSONReturnsNilForInvalidJSON() {
        #expect(StructuredSummary.fromJSON("not json") == nil)
        #expect(StructuredSummary.fromJSON("") == nil)
        #expect(StructuredSummary.fromJSON("{}") == nil) // missing required fields
    }

    @Test func emptyArraysRoundTrip() throws {
        let summary = StructuredSummary(
            summary: "Nothing notable.",
            keyPoints: [],
            actionItems: [],
            sentiment: "neutral"
        )
        let json = summary.toJSON()!
        let restored = StructuredSummary.fromJSON(json)
        #expect(restored?.keyPoints.isEmpty == true)
        #expect(restored?.actionItems.isEmpty == true)
    }

    @Test func specialCharactersInContent() throws {
        let summary = StructuredSummary(
            summary: "Summary with \"quotes\" and newlines\nand tabs\t",
            keyPoints: ["Point with émojis 🎉", "中文测试"],
            actionItems: ["Item with <html> & entities"],
            sentiment: "mixed"
        )
        let json = summary.toJSON()!
        let restored = StructuredSummary.fromJSON(json)!
        #expect(restored == summary)
    }

    // MARK: - SummaryBlock structured content

    @Test func summaryBlockStructuredSummaryDecodesCorrectly() {
        let structured = StructuredSummary(
            summary: "Test",
            keyPoints: ["A"],
            actionItems: ["B"],
            sentiment: "positive"
        )
        let block = SummaryBlock(
            coveringFrom: 0,
            coveringTo: 60,
            content: "Test",
            structuredContent: structured.toJSON()
        )
        #expect(block.structuredSummary != nil)
        #expect(block.structuredSummary?.keyPoints == ["A"])
        #expect(block.structuredSummary?.sentiment == "positive")
    }

    @Test func summaryBlockStructuredSummaryNilWhenNoContent() {
        let block = SummaryBlock(coveringFrom: 0, coveringTo: 60, content: "Test")
        #expect(block.structuredSummary == nil)
        #expect(block.structuredContent == nil)
    }

    @Test func summaryBlockStructuredSummaryNilForInvalidJSON() {
        let block = SummaryBlock(
            coveringFrom: 0,
            coveringTo: 60,
            content: "Test",
            structuredContent: "invalid json"
        )
        #expect(block.structuredSummary == nil)
    }

    // MARK: - SummarySchemaProvider

    @Test func schemaIsValidJSON() throws {
        let schema = SummarySchemaProvider.schema
        #expect(schema.name == "structured_summary")
        #expect(schema.strict == true)

        let parsed = try JSONSerialization.jsonObject(with: schema.schemaData) as? [String: Any]
        #expect(parsed?["type"] as? String == "object")

        let properties = parsed?["properties"] as? [String: Any]
        #expect(properties?["summary"] != nil)
        #expect(properties?["keyPoints"] != nil)
        #expect(properties?["actionItems"] != nil)
        #expect(properties?["sentiment"] != nil)

        let required = parsed?["required"] as? [String]
        #expect(required?.contains("summary") == true)
        #expect(required?.contains("sentiment") == true)
    }

    // MARK: - SummaryMarkdownFormatter structured

    @Test func markdownFormatterIncludesStructuredSections() {
        let structured = StructuredSummary(
            summary: "Meeting went well.",
            keyPoints: ["Goal achieved", "Budget approved"],
            actionItems: ["Send email", "Update docs"],
            sentiment: "positive"
        )
        let markdown = SummaryMarkdownFormatter.format(
            content: "Meeting went well.",
            coveringFrom: 0,
            coveringTo: 300,
            isOverall: true,
            structuredSummary: structured
        )
        #expect(markdown.contains("## Overall Summary"))
        #expect(markdown.contains("Meeting went well."))
        #expect(markdown.contains("### Key Points"))
        #expect(markdown.contains("- Goal achieved"))
        #expect(markdown.contains("### Action Items"))
        #expect(markdown.contains("- [ ] Send email"))
        #expect(markdown.contains("**Sentiment:** positive"))
    }

    @Test func markdownFormatterFallsBackWithoutStructured() {
        let markdown = SummaryMarkdownFormatter.format(
            content: "Plain text summary.",
            coveringFrom: 0,
            coveringTo: 60,
            isOverall: false
        )
        #expect(markdown.contains("Plain text summary."))
        #expect(!markdown.contains("### Key Points"))
    }
}
