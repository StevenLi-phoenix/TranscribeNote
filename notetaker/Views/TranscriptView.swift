import SwiftUI

/// A display item in the transcript: either a single segment or an inline summary replacing a range.
enum TranscriptDisplayItem: Identifiable {
    case segment(TranscriptSegment)
    case summary(SummaryBlock)

    var id: String {
        switch self {
        case .segment(let s): return s.id.uuidString
        case .summary(let s): return "summary-\(s.id)"
        }
    }
}

struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let summaries: [SummaryBlock]
    let partialText: String
    @Binding var scrollToTime: TimeInterval?
    var activeSegmentID: UUID? = nil
    var onTimestampTap: ((TranscriptSegment) -> Void)? = nil

    init(
        segments: [TranscriptSegment],
        partialText: String,
        summaries: [SummaryBlock] = [],
        scrollToTime: Binding<TimeInterval?> = .constant(nil),
        activeSegmentID: UUID? = nil,
        onTimestampTap: ((TranscriptSegment) -> Void)? = nil
    ) {
        self.segments = segments
        self.partialText = partialText
        self.summaries = summaries
        self._scrollToTime = scrollToTime
        self.activeSegmentID = activeSegmentID
        self.onTimestampTap = onTimestampTap
    }

    /// Build a mixed list: segments outside summary ranges shown normally,
    /// segments inside a summary range replaced by the summary (once, at the range start).
    private var displayItems: [TranscriptDisplayItem] {
        // Sort summaries by coveringFrom (non-overall only)
        let sorted = summaries
            .filter { !$0.isOverall }
            .sorted { $0.coveringFrom < $1.coveringFrom }

        guard !sorted.isEmpty else {
            return segments.map { .segment($0) }
        }

        var items: [TranscriptDisplayItem] = []
        var summaryIndex = 0

        for segment in segments {
            // Advance past summaries that end before this segment
            while summaryIndex < sorted.count && sorted[summaryIndex].coveringTo <= segment.startTime {
                summaryIndex += 1
            }

            if summaryIndex < sorted.count {
                let summary = sorted[summaryIndex]
                if segment.startTime >= summary.coveringFrom && segment.startTime < summary.coveringTo {
                    // First segment in range → insert summary
                    if items.last.map({ if case .summary(let s) = $0 { return s.id == summary.id } else { return false } }) != true {
                        items.append(.summary(summary))
                    }
                    // Skip this segment (covered by summary)
                    continue
                }
            }

            items.append(.segment(segment))
        }

        return items
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(displayItems) { item in
                        switch item {
                        case .segment(let segment):
                            TranscriptSegmentRow(
                                segment: segment,
                                isActive: segment.id == activeSegmentID,
                                onTimestampTap: onTimestampTap.map { callback in
                                    { callback(segment) }
                                }
                            )
                            .id(item.id)
                        case .summary(let summary):
                            InlineSummaryRow(
                                coveringFrom: summary.coveringFrom,
                                coveringTo: summary.coveringTo,
                                content: summary.displayContent
                            )
                            .id(item.id)
                            .transition(.opacity)
                        }
                    }

                    // Partial text (current recognition in progress)
                    // Always rendered to avoid layout thrashing from conditional insertion/removal
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Text("...")
                            .font(DS.Typography.timestamp)
                            .foregroundStyle(.secondary)
                            .frame(width: DS.Layout.timestampWidth, alignment: .leading)

                        Text(partialText.isEmpty ? " " : partialText)
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                            .underline(pattern: .dash)
                    }
                    .padding(.vertical, DS.Spacing.xxs)
                    .id("partial")
                    .opacity(partialText.isEmpty ? 0 : 1)
                }
                .padding()
            }
            .onChange(of: segments.count) {
                withAnimation {
                    if let lastSegment = segments.last {
                        proxy.scrollTo(lastSegment.id.uuidString, anchor: .bottom)
                    }
                }
            }
            .onChange(of: partialText.isEmpty) {
                if !partialText.isEmpty {
                    withAnimation {
                        proxy.scrollTo("partial", anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollToTime) { _, time in
                guard let time else { return }
                let target = segments.first { $0.startTime >= time } ?? segments.last
                if let target {
                    withAnimation {
                        proxy.scrollTo(target.id.uuidString, anchor: .top)
                    }
                }
                scrollToTime = nil
            }
            .onChange(of: activeSegmentID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newID.uuidString, anchor: .center)
                }
            }
        }
    }
}

/// Inline summary row that replaces transcript segments in the flow.
struct InlineSummaryRow: View {
    let coveringFrom: TimeInterval
    let coveringTo: TimeInterval
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Text("\(coveringFrom.mmss)–\(coveringTo.mmss)")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: DS.Layout.timestampWidth, alignment: .leading)

            Group {
                if let attributed = try? AttributedString(
                    markdown: content,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attributed)
                } else {
                    Text(content)
                }
            }
            .font(DS.Typography.callout)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
