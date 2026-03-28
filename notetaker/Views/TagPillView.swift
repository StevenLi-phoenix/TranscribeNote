import SwiftUI

struct TagPillView: View {
    let tag: String
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    // 8 predefined tag colors
    private static let tagColors: [Color] = [
        .blue, .purple, .orange, .green, .pink, .teal, .indigo, .mint
    ]

    private var tagColor: Color {
        Self.tagColors[TagParser.colorIndex(for: tag)]
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                pillContent
            }
            .buttonStyle(.plain)
        } else {
            pillContent
        }
    }

    private var pillContent: some View {
        Text(tag)
            .font(DS.Typography.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 2)
            .background(tagColor.opacity(isSelected ? 0.3 : 0.12))
            .foregroundStyle(tagColor)
            .clipShape(Capsule())
            .accessibilityLabel("Tag: \(tag)")
    }
}

/// A horizontal row of tag pills with overflow indicator.
struct TagRow: View {
    let tags: [String]
    var maxVisible: Int = 3
    var selectedTags: Set<String> = []
    var onTagTap: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(Array(tags.prefix(maxVisible)), id: \.self) { tag in
                TagPillView(
                    tag: tag,
                    isSelected: selectedTags.contains(tag),
                    onTap: onTagTap.map { handler in { handler(tag) } }
                )
            }
            if tags.count > maxVisible {
                Text("+\(tags.count - maxVisible)")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
