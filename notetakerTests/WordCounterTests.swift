import Testing
@testable import notetaker

@Suite("WordCounter")
struct WordCounterTests {
    @Test func englishWordCount() {
        #expect(WordCounter.count(in: "Hello world this is a test") == 6)
    }

    @Test func cjkCharCount() {
        #expect(WordCounter.count(in: "今天讨论产品方案") == 8)
    }

    @Test func mixedContent() {
        // CJK dominant: counts chars
        let text = "今天讨论了 product roadmap"
        let count = WordCounter.count(in: text)
        #expect(count > 0)
    }

    @Test func emptyText() {
        #expect(WordCounter.count(in: "") == 0)
        #expect(WordCounter.count(in: "   ") == 0)
    }

    @Test func punctuationFiltered_cjk() {
        // Punctuation should not count as words in CJK
        #expect(WordCounter.count(in: "你好，世界！") == 4) // 你好世界, not 你好，世界！
    }

    @Test func formatMetrics_minutes() {
        let result = WordCounter.formatMetrics(wordCount: 320, duration: 300)
        #expect(result.contains("320"))
        #expect(result.contains("5 min"))
    }

    @Test func formatMetrics_seconds() {
        let result = WordCounter.formatMetrics(wordCount: 50, duration: 45)
        #expect(result.contains("50"))
        #expect(result.contains("45s"))
    }

    @Test func formatMetrics_cjk() {
        let result = WordCounter.formatMetrics(wordCount: 200, duration: 180, isCJK: true)
        #expect(result.contains("字"))
    }

    @Test func isCJKDominant_chinese() {
        #expect(WordCounter.isCJKDominant("今天开会讨论产品"))
    }

    @Test func isCJKDominant_english() {
        #expect(!WordCounter.isCJKDominant("Today we discussed the product"))
    }

    @Test func formatMetrics_minutesAndSeconds() {
        let result = WordCounter.formatMetrics(wordCount: 100, duration: 150) // 2m 30s
        #expect(result.contains("2m"))
        #expect(result.contains("30s"))
    }

    @Test func formatWordCount_english() {
        let result = WordCounter.formatWordCount(wordCount: 500)
        #expect(result == "~500 words")
    }

    @Test func formatWordCount_singular() {
        let result = WordCounter.formatWordCount(wordCount: 1)
        #expect(result == "~1 word")
    }

    @Test func formatWordCount_cjk() {
        let result = WordCounter.formatWordCount(wordCount: 200, isCJK: true)
        #expect(result == "~200 字")
    }
}
