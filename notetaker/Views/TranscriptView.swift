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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(segments, id: \.id) { segment in
                        TranscriptSegmentRow(segment: segment)
                            .id(segment.id)
                    }

                    // Partial text (current recognition in progress)
                    if !partialText.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Text("...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)

                            Text(partialText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .underline(pattern: .dash)
                        }
                        .padding(.vertical, 2)
                        .id("partial")
                    }
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
            .onChange(of: partialText) {
                if !partialText.isEmpty {
                    withAnimation {
                        proxy.scrollTo("partial", anchor: .bottom)
                    }
                }
            }
        }
    }
}
