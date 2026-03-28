import SwiftUI

extension View {
    /// Standard card appearance: padded, rounded, with glass on macOS 26+ or secondary background fallback.
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }

    /// Badge/pill appearance for metadata labels.
    func badgeStyle() -> some View {
        modifier(BadgeStyleModifier())
    }
}

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .padding(DS.Spacing.md)
                .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: DS.Radius.md))
        } else {
            content
                .padding(DS.Spacing.md)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }
}

struct BadgeStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .font(DS.Typography.caption2)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs)
                .glassEffect(.regular.tint(.clear), in: .capsule)
        } else {
            content
                .font(DS.Typography.caption2)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs)
                .background(.quaternary)
                .clipShape(Capsule())
        }
    }
}
