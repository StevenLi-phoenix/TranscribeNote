import SwiftUI

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xxs) {
                Text(segment.startTime.mmss)
                    .font(DS.Typography.timestamp)
                    .foregroundStyle(.secondary)
                    .frame(width: DS.Layout.timestampWidth, alignment: .leading)

                if let sentiment = segment.sentimentValue {
                    Circle()
                        .fill(sentimentColor(sentiment))
                        .frame(width: 6, height: 6)
                        .help(sentiment.rawValue.capitalized)
                        .accessibilityLabel("Sentiment: \(sentiment.rawValue)")
                }
            }

            Text(segment.text)
                .font(DS.Typography.body)
        }
        .padding(.vertical, DS.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private func sentimentColor(_ sentiment: SentimentAnalyzer.Sentiment) -> Color {
        switch sentiment {
        case .neutral: return .gray
        case .positive: return .green
        case .negative: return .red
        case .urgent: return .orange
        case .confused: return .blue
        }
    }
}
