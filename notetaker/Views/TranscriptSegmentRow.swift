import SwiftUI
import os

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    var isActive: Bool = false
    var onTimestampTap: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var showCopiedFeedback = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "TranscriptSegmentRow")

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            timestampLabel
                .frame(width: DS.Layout.timestampWidth, alignment: .leading)

            Text(segment.text)
                .font(DS.Typography.body)
                .textSelection(.enabled)

            Spacer(minLength: DS.Spacing.xs)

            // Copy button — visible on hover or showing feedback
            if isHovered || showCopiedFeedback {
                Button(action: copyText) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(DS.Typography.caption2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showCopiedFeedback ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .help("Copy segment text")
                .accessibilityLabel("Copy segment text to clipboard")
                .transition(.opacity)
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
        .padding(.leading, DS.Spacing.xxs)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(segment.text, forType: .string)
        Self.logger.debug("Copied transcript segment to clipboard (\(segment.text.count) chars)")

        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedFeedback = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedFeedback = false
            }
        }
    }

    // MARK: - Timestamp

    @ViewBuilder
    private var timestampLabel: some View {
        if let onTimestampTap {
            Button(action: onTimestampTap) {
                Text(segment.startTime.mmss)
                    .font(DS.Typography.timestamp)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Jump to \(segment.startTime.mmss)")
            .accessibilityLabel("Seek to \(segment.startTime.mmss)")
        } else {
            Text(segment.startTime.mmss)
                .font(DS.Typography.timestamp)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}
