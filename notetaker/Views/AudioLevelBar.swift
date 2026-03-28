import SwiftUI

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if #available(macOS 26, *) {
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .fill(.clear)
                        .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: DS.Radius.xs))
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.xs)
                        .fill(.quaternary)
                }

                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(DS.Colors.audioLevel.gradient)
                    .frame(width: geometry.size.width * CGFloat(max(0, min(1, level))))
            }
        }
        .frame(height: DS.Spacing.xs)
        .animation(.linear(duration: 0.05), value: level)
        .accessibilityLabel("Audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
