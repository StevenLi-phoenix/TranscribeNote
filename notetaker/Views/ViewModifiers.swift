import SwiftUI

extension View {
    /// Standard card appearance: padded, rounded, with secondary background.
    func cardStyle() -> some View {
        self
            .padding(DS.Spacing.md)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    /// Badge/pill appearance for metadata labels.
    func badgeStyle() -> some View {
        self
            .font(DS.Typography.caption2)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
