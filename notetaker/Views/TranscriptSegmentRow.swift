//
//  TranscriptSegmentRow.swift
//  notetaker
//
//  Created by Steven Li on 2/11/26.
//

import SwiftUI

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(segment.startTime.mmss)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Text content — committed segments always display in primary style
            // (on-device ASR returns confidence 0 for all partials; confidence only
            // appears on task-final results, so gating on confidence is unreliable)
            Text(segment.text)
                .font(.body)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

}
