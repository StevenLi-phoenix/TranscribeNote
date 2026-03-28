import Foundation

/// Token pricing per million tokens for known LLM providers and models.
nonisolated enum TokenPricing {
    struct Rate: Sendable {
        let inputPerMillion: Double   // USD per million input tokens
        let outputPerMillion: Double  // USD per million output tokens
    }

    /// Lookup pricing for a provider + model combination.
    static func rate(provider: LLMProvider, model: String) -> Rate? {
        // Free providers
        if provider == .foundationModels || provider == .ollama {
            return Rate(inputPerMillion: 0, outputPerMillion: 0)
        }

        let modelLower = model.lowercased()

        // OpenAI models
        if modelLower.contains("gpt-4o-mini") { return Rate(inputPerMillion: 0.15, outputPerMillion: 0.60) }
        if modelLower.contains("gpt-4o") { return Rate(inputPerMillion: 2.50, outputPerMillion: 10.0) }
        if modelLower.contains("gpt-4") { return Rate(inputPerMillion: 30.0, outputPerMillion: 60.0) }
        if modelLower.contains("o3-mini") { return Rate(inputPerMillion: 1.10, outputPerMillion: 4.40) }
        if modelLower.contains("o3") { return Rate(inputPerMillion: 2.0, outputPerMillion: 8.0) }
        if modelLower.contains("o4-mini") { return Rate(inputPerMillion: 1.10, outputPerMillion: 4.40) }

        // Anthropic models
        if modelLower.contains("claude-3-5-haiku") || modelLower.contains("claude-haiku") {
            return Rate(inputPerMillion: 0.80, outputPerMillion: 4.0)
        }
        if modelLower.contains("claude-sonnet-4") || modelLower.contains("claude-3-5-sonnet") || modelLower.contains("claude-sonnet") {
            return Rate(inputPerMillion: 3.0, outputPerMillion: 15.0)
        }
        if modelLower.contains("claude-opus") {
            return Rate(inputPerMillion: 15.0, outputPerMillion: 75.0)
        }

        // Gemini models
        if modelLower.contains("gemini") && modelLower.contains("flash") {
            return Rate(inputPerMillion: 0.075, outputPerMillion: 0.30)
        }
        if modelLower.contains("gemini") && modelLower.contains("pro") {
            return Rate(inputPerMillion: 1.25, outputPerMillion: 5.0)
        }

        // Custom/local — unknown pricing
        return nil
    }

    /// Calculate cost for given token usage.
    static func estimateCost(usage: TokenUsage, provider: LLMProvider, model: String) -> Double? {
        guard let rate = rate(provider: provider, model: model) else { return nil }
        let inputCost = Double(usage.inputTokens) / 1_000_000.0 * rate.inputPerMillion
        let outputCost = Double(usage.outputTokens) / 1_000_000.0 * rate.outputPerMillion
        return inputCost + outputCost
    }

    /// Format cost as string: "$0.003" or "Free" or nil for unknown.
    static func formatCost(_ cost: Double?) -> String? {
        guard let cost else { return nil }
        if cost == 0 { return "Free" }
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }

    /// Format token count: "1,234 tokens"
    static func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: count)) ?? "\(count)") tokens"
    }
}
