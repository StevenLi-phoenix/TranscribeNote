import SwiftUI
import Charts
import SwiftData
import os

struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var sessions: [SessionDataPoint] = []
    @State private var selectedPeriod: AnalyticsPeriod = .month

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "notetaker",
        category: "AnalyticsView"
    )

    enum AnalyticsPeriod: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case quarter = "90 Days"

        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                // Period picker
                HStack {
                    Text("Analytics")
                        .font(DS.Typography.title)
                    Spacer()
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(AnalyticsPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                }

                // Summary stat cards
                summaryCards

                // Session frequency bar chart
                sessionFrequencyChart

                // Duration trend line chart
                durationTrendChart
            }
            .padding(DS.Spacing.lg)
        }
        .onAppear { loadData() }
        .onChange(of: selectedPeriod) { _, _ in loadData() }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        let stats = AnalyticsService.summary(sessions: filteredSessions)
        return HStack(spacing: DS.Spacing.md) {
            StatCard(title: "Sessions", value: "\(stats.totalSessions)", icon: "mic.fill")
            StatCard(
                title: "Total Time",
                value: AnalyticsService.formatHoursMinutes(stats.totalDuration),
                icon: "clock.fill"
            )
            StatCard(
                title: "Avg Duration",
                value: AnalyticsService.formatHoursMinutes(stats.averageDuration),
                icon: "chart.bar.fill"
            )
            if let day = stats.mostActiveDay {
                StatCard(title: "Most Active", value: day, icon: "calendar")
            }
        }
    }

    // MARK: - Charts

    private var sessionFrequencyChart: some View {
        let buckets = AnalyticsService.dailyBuckets(sessions: filteredSessions, days: selectedPeriod.days)
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Recording Frequency")
                .font(DS.Typography.sectionHeader)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Date", bucket.date, unit: .day),
                    y: .value("Sessions", bucket.sessionCount)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(DS.Radius.xs)
            }
            .chartXAxis {
                AxisMarks(values: .stride(
                    by: .day,
                    count: selectedPeriod == .week ? 1 : (selectedPeriod == .month ? 7 : 14)
                )) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 200)
        }
        .padding(DS.Spacing.md)
        .cardStyle()
    }

    private var durationTrendChart: some View {
        let buckets = AnalyticsService.dailyBuckets(sessions: filteredSessions, days: selectedPeriod.days)
            .filter { $0.sessionCount > 0 }

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Average Duration")
                .font(DS.Typography.sectionHeader)

            if buckets.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Record some sessions to see trends")
                )
                .frame(height: 200)
            } else {
                Chart(buckets) { bucket in
                    LineMark(
                        x: .value("Date", bucket.date, unit: .day),
                        y: .value("Minutes", bucket.averageDuration / 60)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", bucket.date, unit: .day),
                        y: .value("Minutes", bucket.averageDuration / 60)
                    )
                    .foregroundStyle(.green.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel("Minutes")
                .chartXAxis {
                    AxisMarks(values: .stride(
                        by: .day,
                        count: selectedPeriod == .week ? 1 : 7
                    )) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 200)
            }
        }
        .padding(DS.Spacing.md)
        .cardStyle()
    }

    // MARK: - Data Loading

    private var filteredSessions: [SessionDataPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: Date())!
        return sessions.filter { $0.date >= cutoff }
    }

    private func loadData() {
        do {
            let descriptor = FetchDescriptor<RecordingSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            let allSessions = try modelContext.fetch(descriptor)
            sessions = allSessions.map {
                SessionDataPoint(date: $0.startedAt, duration: $0.totalDuration)
            }
            Self.logger.debug("Loaded \(sessions.count) sessions for analytics")
        } catch {
            Self.logger.error("Failed to load sessions for analytics: \(error.localizedDescription)")
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(DS.Typography.title)
                .fontWeight(.bold)
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.md)
        .cardStyle()
    }
}
