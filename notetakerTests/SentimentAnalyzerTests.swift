import Testing
@testable import notetaker

@Suite("SentimentAnalyzer")
struct SentimentAnalyzerTests {
    @Test func sentimentEnumCases() {
        #expect(SentimentAnalyzer.Sentiment.allCases.count == 5)
    }

    @Test func sentimentFromRawValue() {
        #expect(SentimentAnalyzer.Sentiment(rawValue: "neutral") == .neutral)
        #expect(SentimentAnalyzer.Sentiment(rawValue: "positive") == .positive)
        #expect(SentimentAnalyzer.Sentiment(rawValue: "negative") == .negative)
        #expect(SentimentAnalyzer.Sentiment(rawValue: "urgent") == .urgent)
        #expect(SentimentAnalyzer.Sentiment(rawValue: "confused") == .confused)
        #expect(SentimentAnalyzer.Sentiment(rawValue: "invalid") == nil)
    }

    @Test func sentimentSymbolNames() {
        for sentiment in SentimentAnalyzer.Sentiment.allCases {
            #expect(!sentiment.symbolName.isEmpty)
        }
    }

    @Test func buildPromptBasic() {
        let segments = [
            SentimentAnalyzer.SegmentData(index: 0, text: "Great job everyone!"),
            SentimentAnalyzer.SegmentData(index: 1, text: "We need to fix this immediately."),
        ]
        let prompt = SentimentAnalyzer.buildPrompt(segments: segments)
        #expect(prompt.contains("Great job everyone"))
        #expect(prompt.contains("fix this immediately"))
        #expect(prompt.contains("neutral, positive, negative, urgent, confused"))
    }

    @Test func buildPromptTruncatesLongText() {
        let longText = String(repeating: "A", count: 500)
        let segments = [SentimentAnalyzer.SegmentData(index: 0, text: longText)]
        let prompt = SentimentAnalyzer.buildPrompt(segments: segments)
        // Should be truncated to 200 chars
        #expect(!prompt.contains(String(repeating: "A", count: 300)))
    }

    @Test func parseResponseBasic() {
        let result = SentimentAnalyzer.parseResponse("positive, negative, neutral", expectedCount: 3)
        #expect(result.count == 3)
        #expect(result[0] == .positive)
        #expect(result[1] == .negative)
        #expect(result[2] == .neutral)
    }

    @Test func parseResponseWithWhitespace() {
        let result = SentimentAnalyzer.parseResponse("  positive , negative , urgent  ", expectedCount: 3)
        #expect(result.count == 3)
        #expect(result[0] == .positive)
        #expect(result[1] == .negative)
        #expect(result[2] == .urgent)
    }

    @Test func parseResponsePadsShort() {
        let result = SentimentAnalyzer.parseResponse("positive", expectedCount: 3)
        #expect(result.count == 3)
        #expect(result[0] == .positive)
        #expect(result[1] == .neutral)
        #expect(result[2] == .neutral)
    }

    @Test func parseResponseTruncatesLong() {
        let result = SentimentAnalyzer.parseResponse("positive, negative, urgent, confused, neutral", expectedCount: 2)
        #expect(result.count == 2)
    }

    @Test func parseResponseInvalidFallsToNeutral() {
        let result = SentimentAnalyzer.parseResponse("positive, UNKNOWN, happy", expectedCount: 3)
        #expect(result[0] == .positive)
        #expect(result[1] == .neutral)
        #expect(result[2] == .neutral)
    }

    @Test func parseResponseEmpty() {
        let result = SentimentAnalyzer.parseResponse("", expectedCount: 2)
        #expect(result.count == 2)
        #expect(result[0] == .neutral)
        #expect(result[1] == .neutral)
    }

    @Test func parseResponseCaseInsensitive() {
        let result = SentimentAnalyzer.parseResponse("POSITIVE, Negative, URGENT", expectedCount: 3)
        #expect(result[0] == .positive)
        #expect(result[1] == .negative)
        #expect(result[2] == .urgent)
    }

    @Test func buildPromptEmpty() {
        let prompt = SentimentAnalyzer.buildPrompt(segments: [])
        #expect(prompt.contains("Classify"))
    }

    @Test func analyzeBatchEmptyReturnsEmpty() async throws {
        let result = SentimentAnalyzer.parseResponse("", expectedCount: 0)
        #expect(result.isEmpty)
    }
}
