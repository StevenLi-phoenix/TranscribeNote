import Testing
import Foundation
@testable import notetaker

@Suite(.serialized)
struct TokenCountingTests {

    // Use isolated UserDefaults to prevent cross-test contamination
    private let defaults = UserDefaults(suiteName: "TokenCountingTests")!

    init() {
        defaults.removePersistentDomain(forName: "TokenCountingTests")
    }

    // MARK: - TokenPricing.rate

    @Test func freeProviders() {
        let foundationRate = TokenPricing.rate(provider: .foundationModels, model: "any-model")
        #expect(foundationRate != nil)
        #expect(foundationRate!.inputPerMillion == 0)
        #expect(foundationRate!.outputPerMillion == 0)

        let ollamaRate = TokenPricing.rate(provider: .ollama, model: "llama3")
        #expect(ollamaRate != nil)
        #expect(ollamaRate!.inputPerMillion == 0)
        #expect(ollamaRate!.outputPerMillion == 0)
    }

    @Test func openAIModelPricing() {
        let gpt4oMini = TokenPricing.rate(provider: .openAI, model: "gpt-4o-mini-2024-07-18")
        #expect(gpt4oMini != nil)
        #expect(gpt4oMini!.inputPerMillion == 0.15)

        let gpt4o = TokenPricing.rate(provider: .openAI, model: "gpt-4o")
        #expect(gpt4o != nil)
        #expect(gpt4o!.inputPerMillion == 2.50)

        let o3mini = TokenPricing.rate(provider: .openAI, model: "o3-mini")
        #expect(o3mini != nil)
        #expect(o3mini!.inputPerMillion == 1.10)

        let o4mini = TokenPricing.rate(provider: .openAI, model: "o4-mini-2025-04-16")
        #expect(o4mini != nil)
        #expect(o4mini!.inputPerMillion == 1.10)
    }

    @Test func anthropicModelPricing() {
        let haiku = TokenPricing.rate(provider: .anthropic, model: "claude-3-5-haiku-20241022")
        #expect(haiku != nil)
        #expect(haiku!.inputPerMillion == 0.80)

        let sonnet = TokenPricing.rate(provider: .anthropic, model: "claude-sonnet-4-20250514")
        #expect(sonnet != nil)
        #expect(sonnet!.inputPerMillion == 3.0)

        let opus = TokenPricing.rate(provider: .anthropic, model: "claude-opus-4-20250514")
        #expect(opus != nil)
        #expect(opus!.inputPerMillion == 15.0)
    }

    @Test func geminiModelPricing() {
        let flash = TokenPricing.rate(provider: .openAI, model: "gemini-2.0-flash")
        #expect(flash != nil)
        #expect(flash!.inputPerMillion == 0.075)

        let pro = TokenPricing.rate(provider: .openAI, model: "gemini-1.5-pro")
        #expect(pro != nil)
        #expect(pro!.inputPerMillion == 1.25)
    }

    @Test func unknownModelReturnsNil() {
        let rate = TokenPricing.rate(provider: .openAI, model: "some-unknown-model")
        #expect(rate == nil)

        let customRate = TokenPricing.rate(provider: .custom, model: "local-llama")
        #expect(customRate == nil)
    }

    // MARK: - TokenPricing.estimateCost

    @Test func estimateCostCalculation() {
        let usage = TokenUsage(inputTokens: 1000, outputTokens: 500, cacheCreationTokens: 0, cacheReadTokens: 0)
        let cost = TokenPricing.estimateCost(usage: usage, provider: .openAI, model: "gpt-4o")
        #expect(cost != nil)
        // input: 1000/1M * 2.50 = 0.0025, output: 500/1M * 10.0 = 0.005
        let expected = 0.0025 + 0.005
        #expect(abs(cost! - expected) < 0.0001)
    }

    @Test func estimateCostReturnsNilForUnknown() {
        let usage = TokenUsage(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 0, cacheReadTokens: 0)
        let cost = TokenPricing.estimateCost(usage: usage, provider: .custom, model: "unknown")
        #expect(cost == nil)
    }

    @Test func estimateCostFreeProvider() {
        let usage = TokenUsage(inputTokens: 10000, outputTokens: 5000, cacheCreationTokens: 0, cacheReadTokens: 0)
        let cost = TokenPricing.estimateCost(usage: usage, provider: .ollama, model: "llama3")
        #expect(cost == 0)
    }

    // MARK: - TokenPricing.formatCost

    @Test func formatCostFree() {
        #expect(TokenPricing.formatCost(0) == "Free")
    }

    @Test func formatCostLessThanPenny() {
        #expect(TokenPricing.formatCost(0.005) == "<$0.01")
    }

    @Test func formatCostNormal() {
        #expect(TokenPricing.formatCost(1.23) == "$1.23")
    }

    @Test func formatCostNil() {
        #expect(TokenPricing.formatCost(nil) == nil)
    }

    // MARK: - TokenPricing.formatTokens

    @Test func formatTokensWithCommas() {
        let result = TokenPricing.formatTokens(1234)
        #expect(result == "1,234 tokens")
    }

    @Test func formatTokensZero() {
        let result = TokenPricing.formatTokens(0)
        #expect(result == "0 tokens")
    }

    @Test func formatTokensLarge() {
        let result = TokenPricing.formatTokens(1_000_000)
        #expect(result == "1,000,000 tokens")
    }

    // MARK: - TokenUsageTracker.dateKey

    @Test func dateKeyFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        let date = Calendar.current.date(from: components)!
        let key = TokenUsageTracker.dateKey(date)
        #expect(key == "2026-03-15")
    }

    // MARK: - TokenUsageTracker.record + todayUsage

    @Test func recordAccumulates() {
        let usage1 = TokenUsage(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 0, cacheReadTokens: 0)
        let usage2 = TokenUsage(inputTokens: 200, outputTokens: 75, cacheCreationTokens: 0, cacheReadTokens: 0)

        TokenUsageTracker.record(usage: usage1, estimatedCost: 0.01, defaults: defaults)
        TokenUsageTracker.record(usage: usage2, estimatedCost: 0.02, defaults: defaults)

        let today = TokenUsageTracker.todayUsage(defaults: defaults)
        #expect(today.promptTokens == 300)
        #expect(today.completionTokens == 125)
        #expect(today.requestCount == 2)
        #expect(abs(today.estimatedCost - 0.03) < 0.0001)
    }

    @Test func recordWithNilCost() {
        let usage = TokenUsage(inputTokens: 500, outputTokens: 200, cacheCreationTokens: 0, cacheReadTokens: 0)
        TokenUsageTracker.record(usage: usage, estimatedCost: nil, defaults: defaults)

        let today = TokenUsageTracker.todayUsage(defaults: defaults)
        #expect(today.promptTokens == 500)
        #expect(today.estimatedCost == 0)
    }

    // MARK: - TokenUsageTracker.usage date range

    @Test func usageDateRange() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let usage1 = TokenUsage(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 0, cacheReadTokens: 0)
        let usage2 = TokenUsage(inputTokens: 200, outputTokens: 75, cacheCreationTokens: 0, cacheReadTokens: 0)

        TokenUsageTracker.record(usage: usage1, estimatedCost: 0.01, date: yesterday, defaults: defaults)
        TokenUsageTracker.record(usage: usage2, estimatedCost: 0.02, defaults: defaults) // today

        let week = TokenUsageTracker.weekUsage(defaults: defaults)
        #expect(week.promptTokens == 300)
        #expect(week.completionTokens == 125)
        #expect(week.requestCount == 2)

        let today = TokenUsageTracker.todayUsage(defaults: defaults)
        #expect(today.promptTokens == 200)
        #expect(today.requestCount == 1)
    }

    // MARK: - TokenUsageTracker.resetAll

    @Test func resetAllClearsData() {
        let usage = TokenUsage(inputTokens: 100, outputTokens: 50, cacheCreationTokens: 0, cacheReadTokens: 0)
        TokenUsageTracker.record(usage: usage, estimatedCost: 0.01, defaults: defaults)

        let before = TokenUsageTracker.todayUsage(defaults: defaults)
        #expect(before.requestCount == 1)

        TokenUsageTracker.resetAll(defaults: defaults)

        let after = TokenUsageTracker.todayUsage(defaults: defaults)
        #expect(after.requestCount == 0)
        #expect(after.totalTokens == 0)
    }

    // MARK: - DailyUsage Codable round-trip

    @Test func dailyUsageCodableRoundTrip() throws {
        let original = TokenUsageTracker.DailyUsage(
            promptTokens: 1000,
            completionTokens: 500,
            requestCount: 5,
            estimatedCost: 0.15
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TokenUsageTracker.DailyUsage.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - DailyUsage totalTokens

    @Test func dailyUsageTotalTokens() {
        let usage = TokenUsageTracker.DailyUsage(promptTokens: 300, completionTokens: 200, requestCount: 1, estimatedCost: 0)
        #expect(usage.totalTokens == 500)
    }
}
