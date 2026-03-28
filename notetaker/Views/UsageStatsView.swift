import SwiftUI

/// Settings tab showing cumulative token usage and cost statistics.
struct UsageStatsView: View {
    @State private var todayUsage = TokenUsageTracker.DailyUsage()
    @State private var weekUsage = TokenUsageTracker.DailyUsage()
    @State private var monthUsage = TokenUsageTracker.DailyUsage()
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text("Token Usage")
                .font(DS.Typography.title)

            HStack(alignment: .top, spacing: DS.Spacing.lg) {
                usageCard(title: "Today", usage: todayUsage)
                usageCard(title: "This Week", usage: weekUsage)
                usageCard(title: "This Month", usage: monthUsage)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Reset Usage Data") {
                    showResetConfirmation = true
                }
                .alert("Reset Usage Data?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        TokenUsageTracker.resetAll()
                        refreshUsage()
                    }
                } message: {
                    Text("This will permanently delete all accumulated token usage statistics.")
                }
            }
        }
        .padding(DS.Spacing.xl)
        .onAppear { refreshUsage() }
    }

    private func usageCard(title: String, usage: TokenUsageTracker.DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(DS.Typography.sectionHeader)

            Divider()

            statRow(label: "Total Tokens", value: TokenPricing.formatTokens(usage.totalTokens))
            statRow(label: "Input", value: TokenPricing.formatTokens(usage.promptTokens))
            statRow(label: "Output", value: TokenPricing.formatTokens(usage.completionTokens))
            statRow(label: "Requests", value: "\(usage.requestCount)")

            Divider()

            statRow(label: "Est. Cost", value: costDisplay(usage.estimatedCost))
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(DS.Typography.callout)
        }
    }

    private func costDisplay(_ cost: Double) -> String {
        if cost == 0 { return "Free" }
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }

    private func refreshUsage() {
        todayUsage = TokenUsageTracker.todayUsage()
        weekUsage = TokenUsageTracker.weekUsage()
        monthUsage = TokenUsageTracker.monthUsage()
    }
}
