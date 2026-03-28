import SwiftUI

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(.quaternary)

                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(DS.Colors.audioLevel)
                    .frame(width: geometry.size.width * CGFloat(max(0, min(1, level))))
            }
        }
        .frame(height: DS.Spacing.xs)
        .animation(.spring(duration: 0.15, bounce: 0.0), value: level)
        .accessibilityLabel("Audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
