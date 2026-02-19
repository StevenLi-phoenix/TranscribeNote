//
//  TranscriptView.swift
//  notetaker
//
//  Created by Steven Li on 2/11/26.
//

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
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(segments, id: \.id) { segment in
                        TranscriptSegmentRow(segment: segment)
                            .id(segment.id)
                    }

                    // Partial text (current recognition in progress)
                    // Always rendered to avoid layout thrashing from conditional insertion/removal
                    HStack(alignment: .top, spacing: 12) {
                        Text("...")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)

                        Text(partialText.isEmpty ? " " : partialText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .underline(pattern: .dash)
                    }
                    .padding(.vertical, 2)
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
                // Find first segment at or after the requested time
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
