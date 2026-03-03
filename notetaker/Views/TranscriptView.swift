import SwiftUI

struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let partialText: String
    @Binding var scrollToTime: TimeInterval?

    init(segments: [TranscriptSegment], partialText: String, scrollToTime: Binding<TimeInterval?> = .constant(nil)) {
        self.segments = segments
        self.partialText = partialText
        self._scrollToTime = scrollToTime
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(segments, id: \.id) { segment in
                        TranscriptSegmentRow(segment: segment)
                            .id(segment.id)
                    }

                    // Partial text (current recognition in progress)
                    // Always rendered to avoid layout thrashing from conditional insertion/removal
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Text("...")
                            .font(DS.Typography.timestamp)
                            .foregroundStyle(.secondary)
                            .frame(width: DS.Layout.timestampWidth, alignment: .trailing)

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
                        proxy.scrollTo(lastSegment.id, anchor: .bottom)
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
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
                scrollToTime = nil
            }
        }
    }
}
