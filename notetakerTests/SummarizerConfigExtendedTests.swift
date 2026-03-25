import Testing
import Foundation
@testable import notetaker

@Suite("SummarizerConfig Extended Tests", .serialized)
struct SummarizerConfigExtendedTests {

    private let testDefaults: UserDefaults
    private let suiteName = "com.notetaker.test.SummarizerConfigExtendedTests"

    init() {
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Defaults

    @Test func defaultValues() {
        let config = SummarizerConfig.default
        #expect(config.liveSummarizationEnabled == true)
        #expect(config.intervalMinutes == 1)
        #expect(config.minTranscriptLength == 100)
        #expect(config.summaryLanguage == "auto")
        #expect(config.summaryStyle == .bullets)
        #expect(config.includeContext == true)
        #expect(config.maxContextTokens == 2000)
        #expect(config.overallSummaryMode == .auto)
    }

    // MARK: - Custom Init

    @Test func customInit() {
        let config = SummarizerConfig(
            liveSummarizationEnabled: false,
            intervalMinutes: 5,
            minTranscriptLength: 200,
            summaryLanguage: "zh",
            summaryStyle: .paragraph,
            includeContext: false,
            maxContextTokens: 1000,
            overallSummaryMode: .rawText
        )
        #expect(config.liveSummarizationEnabled == false)
        #expect(config.intervalMinutes == 5)
        #expect(config.minTranscriptLength == 200)
        #expect(config.summaryLanguage == "zh")
        #expect(config.summaryStyle == .paragraph)
        #expect(config.includeContext == false)
        #expect(config.maxContextTokens == 1000)
        #expect(config.overallSummaryMode == .rawText)
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        let original = SummarizerConfig(
            liveSummarizationEnabled: false,
            intervalMinutes: 3,
            minTranscriptLength: 50,
            summaryLanguage: "ja",
            summaryStyle: .actionItems,
            includeContext: true,
            maxContextTokens: 3000,
            overallSummaryMode: .chunkSummaries
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SummarizerConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test func decodingWithoutOptionalFieldsUsesDefaults() throws {
        // liveSummarizationEnabled and overallSummaryMode use decodeIfPresent
        let json = """
        {"intervalMinutes":2,"minTranscriptLength":50,"summaryLanguage":"en","summaryStyle":"paragraph","includeContext":true,"maxContextTokens":1000}
        """
        let config = try JSONDecoder().decode(SummarizerConfig.self, from: json.data(using: .utf8)!)
        #expect(config.liveSummarizationEnabled == true) // default
        #expect(config.overallSummaryMode == .auto) // default
        #expect(config.intervalMinutes == 2)
        #expect(config.summaryStyle == .paragraph)
    }

    // MARK: - fromUserDefaults

    @Test func fromUserDefaultsReturnsDefaultWhenEmpty() {
        let key = "testSumConfig_\(UUID().uuidString)"
        let config = SummarizerConfig.fromUserDefaults(key: key, defaults: testDefaults)
        #expect(config == .default)
    }

    @Test func fromUserDefaultsDecodesJSON() {
        let key = "testSumConfig_\(UUID().uuidString)"
        let json = """
        {"liveSummarizationEnabled":false,"intervalMinutes":10,"minTranscriptLength":500,"summaryLanguage":"ko","summaryStyle":"lectureNotes","includeContext":false,"maxContextTokens":5000,"overallSummaryMode":"rawText"}
        """
        testDefaults.set(json, forKey: key)

        let config = SummarizerConfig.fromUserDefaults(key: key, defaults: testDefaults)
        #expect(config.liveSummarizationEnabled == false)
        #expect(config.intervalMinutes == 10)
        #expect(config.summaryStyle == .lectureNotes)
        #expect(config.overallSummaryMode == .rawText)
    }

    @Test func fromUserDefaultsReturnsDefaultForInvalidJSON() {
        let key = "testSumConfig_\(UUID().uuidString)"
        testDefaults.set("{invalid", forKey: key)

        let config = SummarizerConfig.fromUserDefaults(key: key, defaults: testDefaults)
        #expect(config == .default)
    }

    // MARK: - Equatable

    @Test func equatable() {
        let a = SummarizerConfig.default
        let b = SummarizerConfig.default
        #expect(a == b)
    }

    @Test func notEqual() {
        let a = SummarizerConfig.default
        let b = SummarizerConfig(intervalMinutes: 99)
        #expect(a != b)
    }
}

// MARK: - SummaryStyle Tests

@Suite("SummaryStyle Tests")
struct SummaryStyleTests {

    @Test func allCases() {
        #expect(SummaryStyle.allCases.count == 4)
        #expect(SummaryStyle.allCases.contains(.bullets))
        #expect(SummaryStyle.allCases.contains(.paragraph))
        #expect(SummaryStyle.allCases.contains(.actionItems))
        #expect(SummaryStyle.allCases.contains(.lectureNotes))
    }

    @Test func rawValues() {
        #expect(SummaryStyle.bullets.rawValue == "bullets")
        #expect(SummaryStyle.paragraph.rawValue == "paragraph")
        #expect(SummaryStyle.actionItems.rawValue == "actionItems")
        #expect(SummaryStyle.lectureNotes.rawValue == "lectureNotes")
    }

    @Test func codableRoundTrip() throws {
        for style in SummaryStyle.allCases {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(SummaryStyle.self, from: data)
            #expect(decoded == style)
        }
    }
}

// MARK: - OverallSummaryMode Tests

@Suite("OverallSummaryMode Tests")
struct OverallSummaryModeTests {

    @Test func allCases() {
        #expect(OverallSummaryMode.allCases.count == 3)
        #expect(OverallSummaryMode.allCases.contains(.rawText))
        #expect(OverallSummaryMode.allCases.contains(.chunkSummaries))
        #expect(OverallSummaryMode.allCases.contains(.auto))
    }

    @Test func rawValues() {
        #expect(OverallSummaryMode.rawText.rawValue == "rawText")
        #expect(OverallSummaryMode.chunkSummaries.rawValue == "chunkSummaries")
        #expect(OverallSummaryMode.auto.rawValue == "auto")
    }

    @Test func codableRoundTrip() throws {
        for mode in OverallSummaryMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(OverallSummaryMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}

// MARK: - SummaryBlock Extended Tests

@Suite("SummaryBlock Extended Tests")
struct SummaryBlockExtendedTests {

    @Test func displayContentReturnsContentWhenNoEdit() {
        let block = SummaryBlock(coveringFrom: 0, coveringTo: 60, content: "Original")
        #expect(block.displayContent == "Original")
    }

    @Test func displayContentReturnsEditedContent() {
        let block = SummaryBlock(coveringFrom: 0, coveringTo: 60, content: "Original", editedContent: "Edited")
        #expect(block.displayContent == "Edited")
    }

    @Test func summaryStyleFromString() {
        let block = SummaryBlock(coveringFrom: 0, coveringTo: 60, content: "Test", style: .paragraph)
        #expect(block.summaryStyle == .paragraph)
        #expect(block.style == "paragraph")
    }

    @Test func summaryStyleDefaultsToBullets() {
        let block = SummaryBlock(coveringFrom: 0, coveringTo: 60, content: "Test")
        block.style = "invalidStyle"
        #expect(block.summaryStyle == .bullets)
    }

    @Test func isOverallDefault() {
        let block = SummaryBlock(coveringFrom: 0, coveringTo: 60, content: "Test")
        #expect(block.isOverall == false)
    }

    @Test func isOverallTrue() {
        let block = SummaryBlock(coveringFrom: 0, coveringTo: 60, content: "Test", isOverall: true)
        #expect(block.isOverall == true)
    }

    @Test func initAllParams() {
        let id = UUID()
        let date = Date()
        let block = SummaryBlock(
            id: id,
            generatedAt: date,
            coveringFrom: 10,
            coveringTo: 120,
            content: "Summary",
            style: .actionItems,
            model: "gpt-4",
            isPinned: true,
            userEdited: true,
            isOverall: true,
            editedContent: "Edited summary"
        )
        #expect(block.id == id)
        #expect(block.generatedAt == date)
        #expect(block.coveringFrom == 10)
        #expect(block.coveringTo == 120)
        #expect(block.content == "Summary")
        #expect(block.summaryStyle == .actionItems)
        #expect(block.model == "gpt-4")
        #expect(block.isPinned == true)
        #expect(block.userEdited == true)
        #expect(block.isOverall == true)
        #expect(block.editedContent == "Edited summary")
        #expect(block.displayContent == "Edited summary")
    }
}
