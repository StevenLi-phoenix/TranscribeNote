import SwiftUI

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Text(segment.startTime.mmss)
                .font(DS.Typography.timestamp)
                .foregroundStyle(.secondary)
                .frame(width: DS.Layout.timestampWidth, alignment: .trailing)

            Text(segment.text)
                .font(DS.Typography.body)
        }
        .padding(.vertical, DS.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
